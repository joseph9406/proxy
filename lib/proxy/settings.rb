require "yaml"
require "ostruct"
require "pathname"

require 'proxy/settings/global'

module Proxy::Settings
  # Pathname.new(__dir__); 创建了一个 Pathname 对象，表示当前文件所在的目录的路径。  
  SETTINGS_PATH = Pathname.new(__dir__).join("..", "..", "config", "settings.yml")  # "__dir__" 指向包含當前腳本文件的目錄的字符串  
  
  #def self.initialize_global_settings(settings_path = nil, argv = ARGV)     
  def self.initialize_settings(settings_path = nil, argv = ARGV)    
    global = ::Proxy::Settings::Global.new(YAML.load(File.read(settings_path || SETTINGS_PATH))) # YAML.load 用于将YAML格式的字符串转换为Ruby对象(即hash)
    global.apply_argv(argv)
    global
  end

  def self.read_settings_file(settings_file, settings_directory = nil)
    puts "*** ::Proxy::SETTINGS.settings_directory = #{::Proxy::SETTINGS.settings_directory} ***"
    YAML.load(File.read(File.join(settings_directory || ::Proxy::SETTINGS.settings_directory, settings_file))) || {}
  end
    
end