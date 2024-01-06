# frozen_string_literal: true

#===================================== gem 入口文件 =========================================================================
# 与 gem 名称相同的 .rb 文件，称为 "gem 主文件" 或 "gem 驱动文件", 用于加载整个 gem 的代码和功能,視為該 gem 的入口文件。
# 例如, 本文件 proxy.rb 就是 proxy gem 的主文件或驅動文件。
# 通常这个文件的作用是用于执行 gem 的初始化工作,例如, 配置 gem 的功能、设置环境变量,加载其他相關的模块、类和方法等。
# 当在 Ruby 项目中使用 require 'proxy' 以加载 proxy.rb 文件並執行裏面的代碼。
#
# 执行 bundle install 主要用于安装项目中所需的 gem，以及安装它们的依赖项, 并不会自动加载与 gem 同名的主文件。 
# bundle install 这个命令的目标是将 gem 安装到项目的 gemset 中，而不是加载它们的代码。
# 在 Ruby on Rails 项目中，通常使用 config/application.rb 文件来加载 gem，这个文件可以配置需要加载的 gem，
# 并使用 require 来加载它们的主文件。这可以在 Rails 项目中自动加载 gem 的功能。
#============================================================================================================================
APP_ROOT = "#{__dir__}/.."
require "proxy/version"  # 在 proxy/version.rb裏有定義 module Proxy; 最好先把根源 Proxy 先在 version.rb 中先定義好。
require 'logging'
require "smart_proxy_main"

require 'proxy/log'
require 'proxy/settings/plugin'

require 'proxy/pluggable'
require 'proxy/plugins'
require 'proxy/plugin'
require 'proxy/provider_factory'
require 'proxy/provider'

require 'bundler_helper'

require 'proxy/dependency_injection'
require 'proxy/plugin_initializer'
require 'proxy/plugin_validators'

require 'webrick/https'  # 尽管 webrick 是 Ruby 的标准库之一，但在使用 Bundler.require 时，它可能会遇到加载的问题。所以還是在Gemfile中顯示的添加。
require 'rack'
require 'launcher'

#Proxy::Launcher.new.launch

