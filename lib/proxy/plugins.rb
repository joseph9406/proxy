class ::Proxy::PluginNotFound < ::StandardError; end
class ::Proxy::PluginVersionMismatch < ::StandardError; end
class ::Proxy::PluginMisconfigured < ::StandardError; end
class ::Proxy::PluginProviderNotFound < ::StandardError; end
class ::Proxy::PluginLoadingAborted < ::StandardError; end

class Proxy::Plugins
  include ::Proxy::Log  

  # 如果 @instance 实例变量还没有被赋值，那么创建一个新的 Proxy::Plugins 实例，并将其赋值给 @instance。
  # 在之后的调用中，self.instance 方法将直接返回已存在的 @instance 实例，而不会重复创建新的实例。
  # @instance 是這個類本身的實例變量,是依附在這個類本身的,不是依附在類實例上。
  def self.instance
    @instance ||= Proxy::Plugins.new
  end

  attr_writer :loaded # 若是 attr_reader :loaded, 則在 plugin_loaded 方法中的 self.loaded 就無法寫入。
  def loaded
    @loaded ||= []
  end

  def plugin_loaded(_name, _version, _class)    
    # 若是添加元素, loaded << {:name => _name, :version => _version, :class => _class, :state => :uninitialized}
    # 若是掭加另一個數組中的元素,用 "+"。    
    self.loaded += [{:name => _name, :version => _version, :class => _class, :state => :uninitialized}]
    # 在实例方法中的 self 表示該實例方法的調用者(即這個實例本身), 
    # 上述代碼可以省略 self,这是 Ruby 的一种隐式约定,使得代码更加简洁。
    # loaded += [{:name => _name, :version => _version, :class => _class, :state => :uninitialized}] 
  end

  # 從 loaded 陣列中刪除同名的舊插件，並將已更新的插件添加到 loaded 陣列中，從而更新插件。
  def update(updated_plugins)
    updated_plugins.each do |updated|
      loaded.delete_if { |p| p[:name] == updated[:name] }
      loaded << updated
    end
  end

  # 迭代 loaded 數組,將 loaded 數組中的每個元素傳遞給塊,以塊做為過濾條件,返回第一個符合條件的元素。
  def find
    loaded.find do |plugin|  # 此行的 find 是数组的一个迭代方法，它接受一个块（block）作为参数。
      # 塊（block）中的程式碼用於檢查 plugin 數組中的元素是否滿足條件。
      # 如果塊返回一個真值（true 或非 nil），則 find 方法會停止迭代並返回該元素 plugin。(即為第一個符合條件的元素)
      yield plugin  
    end
  end

  # 迭代 loaded 數組,將 loaded 數組中的每個元素傳遞給塊,以塊做為過濾條件返回一個新數組。
  def select
    loaded.select do |plugin|   # 将根据块中的条件筛选出满足条件的插件，并返回一个新的数组。
      yield plugin
    end
  end
  

end