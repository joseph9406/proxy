module Proxy::DependencyInjection
  class InstanceValiableWrapper
    def initialize(a_class_or_lambda)
      @a_class_or_lambda = a_class_or_lambda
    end

    def instance  # 每次調用 instance 方法時,都會產生一個新的實例   
      @a_class_or_lambda.respond_to?(:call) ? @a_class_or_lambda.call : @a_class_or_lambda.new
    end
  end
  
  class SingletonWrapper
    def initialize(a_class_or_lambda)
      @an_instance = a_class_or_lambda.respond_to?(:call) ? a_class_or_lambda.call : a_class_or_lambda.new   
    end

    def instance  # 調用 instance 方法時,只會返回原先在initialize初始化時所產生的實例,不會產生新實例。
      @an_instance
    end

  end
  
  module Wiring
    def singleton_dependency(var_name, a_class_or_lambda)
      container = container_instance
      container.singleton_dependency(var_name, a_class_or_lambda)
    end

    def dependency(var_name, a_class)
      container = container_instance
      container.dependency(var_name, a_class)
    end
  end
  
  class Container
    def initialize
      yield(self) if block_given?        
    end

    def dependencies
      @dependencies ||= {}
    end

    def add_dependency(var_name, a_wrapper)
      dependencies[var_name] = a_wrapper
    end    

    def dependency(var_name, a_class)        
      add_dependency(var_name, Proxy::DependencyInjection::InstanceVariableWrapper.new(a_class))
    end

    def singleton_dependency(var_name, a_class_or_lambda)        
      add_dependency(var_name, Proxy::DependencyInjection::SingletonWrapper.new(a_class_or_lambda))
    end

    def get_dependency(var_name)
      raise "Dependency '#{var_name}' is undefined" unless dependencies.key?(var_name)
      dependencies[var_name].instance
    end

    def container_instance
      self
    end

    def self.instance
      @@instance ||= new
    end

  end
  
  module Accessors
    def inject_attr(reference, local_var)
      container = container_instance
      define_method(local_var.to_sym) do
        if instance_variable_get("@#{local_var}").nil?
          instance_variable_set("@#{local_var}", container.get_dependency(reference))
        else
          instance_variable_get("@#{local_var}")
        end
      end
      define_method("#{local_var}=") do |val|
        instance_variable_set("@#{local_var}", val)
      end
    end
  end
end
  