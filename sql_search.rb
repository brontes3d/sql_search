#TODO: when paramix are available standard from facets again... make this a plugin
module SqlSearch
  include MyParamix
  
  def self.included(base)
    # puts "parametric_options: " + base.mixin_parameters.inspect
    
    params = base.mixin_parameters[SqlSearch]
    # base.mixin_parameters[self]
    extension = Module.new
    
    conditions = params[:on]
    includes = params[:include]
    order = params[:order]
    search_via_association = params[:search_via_association]

    search_implementation = Proc.new do |search_params, extra_options|
      unless extra_options[:order].blank?
        order = extra_options.delete(:order)
      end
      
      if search_via_association
        klass, call_on_results = search_via_association
        klass.class_eval do
          with_scope(:find => extra_options) do
            SqlSearch.run_search(klass, search_params, conditions, includes, order)
          end
        end.collect do |result| 
          result.send(call_on_results)
        end.flatten
      else
        with_scope(:find => extra_options) do
          SqlSearch.run_search(base, search_params, conditions, includes, order)
        end
      end
    end
    
    extension.send(:define_method, :search_implementation, &search_implementation)

    base.extend(extension)
    
    base.class_eval do      
      def self.search(search_params, extra_options = {})
        self.search_implementation(search_params, extra_options)
      end
    end    
  end
  
  #appraoch to search on multiple terms
  #is to find all results for each term
  #and then determine the intersect
  #if this proves to be a bottleneck, we should instead fetch all ids
  #then after caculating intersect of ids
  #we can select the full models which match the set of ids
  def self.run_search(on_class, search_params, conditions, includes, order)
    things_found = nil
    or_concat_of_conditions = conditions.collect{|cond| "LOWER(#{cond}) LIKE :term"}.join(" OR ")
    
    make_conditions = Proc.new do |search_term|
      {
        :conditions => [or_concat_of_conditions,
          {:term => "%#{search_term}%"}],
        :include => includes,
        :order => order
      }
    end
    search_params.split(" ").each do |term|
      if things_found  
        things_found = things_found & on_class.find(:all, make_conditions.call(term))
      else
        things_found = on_class.find(:all, make_conditions.call(term)) #Case.matching_search_for_single_term(term)
      end
    end
    things_found || []    
  end
  
end