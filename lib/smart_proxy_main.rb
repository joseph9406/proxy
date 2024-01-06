# 以下 require "proxy/settings", 其中, "proxy/setting.rb" 文件中是有用到 module Proxy::Settings
# 所以, module Proxy 的定義必須先存在,才能把這些 require "proxy/settings" 放在開頭。
# 而 module Proxy 的定義是通過 proxy.rb 入口來處理的。
require 'proxy/settings'

module Proxy  
  #SETTINGS = Settings.initialize_global_settings
  SETTINGS = Settings.initialize_settings  # 這裏的"Settings"是指 module Proxy::Settings, initialize_settings是該 module 的方法。

  # (1)chomp,移除字符串末尾的换行符（\n）。这是为了确保读取的文件内容不包含换行符，通常用于处理文本文件中的行末换行符。
  # (2)File.join 是一个用于构建文件路径的方法。它接受多个参数，根据当前操作系统的路径分隔符来正确连接這些参数，
  #    将它们连接起来以创建一个完整的文件路径，使路径在不同操作系统上都可用。 
  #    通常，在不同操作系统上，文件路径的分隔符是不同的。例如，在Unix和Linux系统上，通常使用斜杠（/）作为路径分隔符，
  #    而在Windows系统上使用反斜杠（\）作为路径分隔符。
  #VERSION = File.read(File.join(__dir__, '..', 'VERSION')).chomp  
end

