require 'proxy/log'
#require 'proxy/plugins'
require 'proxy/signal_handler'

require 'proxy/log_buffer/trace_decorator'
require 'sd_notify'

CIPHERS = ['ECDHE-RSA-AES128-GCM-SHA256', 'ECDHE-RSA-AES256-GCM-SHA384',
           'AES128-GCM-SHA256', 'AES256-GCM-SHA384', 'AES128-SHA256',
           'AES256-SHA256', 'AES128-SHA', 'AES256-SHA'].freeze

module Proxy
  class Launcher
    include ::Proxy::Log

    attr_reader :settings
   
    def initialize(settings = SETTINGS)  
      # 目前只能用root執行,才會寫入log,
      logger.info("** (A) logger 功能正常, 執行 Proxy::Launcher 初始化 ... ***")  
      @settings = settings
      myputs       
    end

    def pid_path
      settings.daemon_pid
    end

    def http_enabled?
      !settings.http_port.nil?
    end

    def https_enabled?
      settings.ssl_private_key && settings.ssl_certificate && settings.ssl_ca_file
    end
    
    def plugins    # ::proyx::Plugins 中包含了所有已安裝的 plugin 插件,再從中篩選出"執行中"的插件,返回結果是一組數組。
      ::Proxy::Plugins.instance.select { |p| p[:state] == :running }  # 根据块中的条件筛选出满足条件的插件，并返回一个新的数组。
    end

    # 再依據前述的 plugins 方法,繼續做篩選
    def http_plugins
      plugins.select { |p| p[:http_enabled] }.map { |p| p[:class] }
    end

    def https_plugins
      plugins.select { |p| p[:https_enabled] }.map { |p| p[:class] }
    end

    def http_app(http_port, plugins = http_plugins)
      return nil unless http_enabled?
      # 使用 Rack::Builder.new 创建一个 Rack 构建器对象 app，该构建器将用于配置 Rack 应用程序。      
      app = Rack::Builder.new do
        #====================================================================================
        # 这里的 http_rackup 是每个插件对象中定义的方法，该方法会返回 Rack 应用的配置。
        # 然后通过 instance_eval 执行这个方法，将其效果应用到当前的 Rack::Builder 实例中。
        #====================================================================================
        plugins.each { |p| instance_eval(p.http_rackup) }  
      end

      {
        :app => app,
        :server => :webrick,
        :DoNotListen => true,
        :Port => http_port, # only being used to correctly log http port being used
        :Logger => ::Proxy::LogBuffer::TraceDecorator.instance,
        :AccessLog => [],
        :ServerSoftware => "foreman-proxy/#{Proxy::VERSION}",
        :daemonize => false,
      }
    end

    def https_app(https_port, plugins = https_plugins)
      unless https_enabled?
        logger.warn "Missing SSL setup, https is disabled."
        return nil
      end

      app = Rack::Builder.new do
        plugins.each { |p| instance_eval(p.https_rackup) }
      end

      #======================================================================================================================================  
      # 通过禁用这些不安全的协议版本和弱密码套件，可以提高 SSL/TLS 的整体安全性，确保系统使用更现代、更安全的加密标准。
      # 这对于防范针对协议漏洞和密码学弱点的攻击非常重要。
      #
      # ssl_options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
      #   这行代码的作用是获取 OpenSSL::SSL::SSLContext 模块中的默认 SSL 参数的"选项部分"。
      #   在 Ruby 的 OpenSSL 库中，SSLContext::DEFAULT_PARAMS 是一个 Hash，包含了一组默认的 SSL/TLS 参数。如下:
      #   {:min_version=>769, :verify_mode=>1, :verify_hostname=>true, :options=>2147614804}
      #   具体而言，[:options] 键用于检索默认参数中的选项部分。在 SSL/TLS 上下文中，选项是一个表示各种 SSL/TLS 选项的整数，
      #   通过按位 OR 运算符 | 可以设置不同的选项。
      #   因此，ssl_options 将包含默认 SSL/TLS 参数的选项部分，你可以使用它在后续代码中设置 SSL/TLS 上下文的选项。
      #
      # OpenSSL::SSL 模块中包含了一系列用于配置 SSL/TLS 行为的常量。这些常量代表一些选项，可以通过按位 OR 操作进行组合，以实现特定的 SSL/TLS 配置。
      # 以下是一些常见的 OpenSSL::SSL 常量及其作用：
      # (1) OP_NO_SSLv2, OP_NO_SSLv3, OP_NO_TLSv1, OP_NO_TLSv1_1, OP_NO_TLSv1_2:
      #    这些常量分别表示禁用 SSLv2、SSLv3、TLSv1、TLSv1.1、TLSv1.2 协议版本。通过将这些常量组合使用，可以配置 SSL/TLS 上下文以排除不安全的协议版本。
      # (2) OP_CIPHER_SERVER_PREFERENCE: 表示服务端对密码套件的偏好。如果设置了这个选项，服务端将优先选择服务端密码套件列表中的密码套件。
      # 
      # 这些常量通常用于设置 SSL/TLS 上下文的选项，例如 OpenSSL::SSL::SSLContext.new(options)，其中 options 是通过按位 OR 组合这些常量生成的。
      # 这些选项用于控制 SSL/TLS 握手过程中的协议版本、密码套件和其他安全配置。
      #=======================================================================================================================================
      ssl_options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]       
      # 这个选项表示在使用服务器密码时,优先选择服"务器密码套件"而不是"客户端密码套件"。
      ssl_options |= OpenSSL::SSL::OP_CIPHER_SERVER_PREFERENCE if defined?(OpenSSL::SSL::OP_CIPHER_SERVER_PREFERENCE)
      # This is required to disable SSLv3 on Ruby 1.8.7
      ssl_options |= OpenSSL::SSL::OP_NO_SSLv2 if defined?(OpenSSL::SSL::OP_NO_SSLv2) # OpenSSL::SSL::OP_NO_SSLv2,禁用 SSLv2 协议
      ssl_options |= OpenSSL::SSL::OP_NO_SSLv3 if defined?(OpenSSL::SSL::OP_NO_SSLv3) # SLv3 也存在一些安全漏洞，包括 POODLE 攻击。禁用 SSLv3 可以防止使用这个存在漏洞的协议版本。
      ssl_options |= OpenSSL::SSL::OP_NO_TLSv1 if defined?(OpenSSL::SSL::OP_NO_TLSv1) #  TLSv1.0 是一个较早的 TLS 版本，也存在一些安全问题。禁用 TLSv1 可以防止使用这个较旧的 TLS 协议版本。
      ssl_options |= OpenSSL::SSL::OP_NO_TLSv1_1 if defined?(OpenSSL::SSL::OP_NO_TLSv1_1)  # TLSv1.1 是 TLS 的一个较早版本，为提高安全性，禁用 TLSv1.1 可以防止使用这个相对较旧的版本。
      
      # Proxy::SETTINGS.tls_disabled_versions：这是一个数组，其中包含要禁用的 TLS 版本。通过循环迭代数组，将 OpenSSL 中相应的常量添加到 ssl_options 中。
      Proxy::SETTINGS.tls_disabled_versions&.each do |version|  
        # tr('.', '_') 方法将版本号中的点号替换为下划线。这是因为在常量命名中，通常用下划线替代点号。
        # const_get 是 Ruby 提供的一个方法，用于获取模块或类中的常量。它通过常量的名称字符串在运行时动态地获取常量的值。
        constant = OpenSSL::SSL.const_get("OP_NO_TLSv#{version.to_s.tr('.', '_')}") rescue nil   # 如果指定的常量不存在，const_get 将引发 NameError,所以才需要 "rescue nil"

        if constant
          logger.info "TLSv#{version} will be disabled."
          ssl_options |= constant
        else
          logger.warn "TLSv#{version} was not found."
        end
      end

      {
        :app => app,
        :server => :webrick,
        :DoNotListen => true,   # 不会尝试监听任何地址或端口。这可以防止不必要的网络监听，特别是在一些特定用例中，服务器只需要处理内部请求或通过其他方式与外部通信。
        :Port => https_port, # only being used to correctly log https port being used
        :Logger => ::Proxy::LogBuffer::Decorator.instance,
        #:ServerSoftware => "foreman-proxy/#{Proxy::VERSION}",
        :SSLEnable => true,
        #:SSLVerifyClient => OpenSSL::SSL::VERIFY_PEER,  #  表示要验证客户端的证书。如果客户端未提供有效的证书，连接将被拒绝。
        :SSLPrivateKey => load_ssl_private_key(settings.ssl_private_key),   # 服務器私钥是与服务器证书配对的(證書裏有服務器公鈅)，用于建立安全连接。
        :SSLCertificate => load_ssl_certificate(settings.ssl_certificate),  # 服务器证书
        :SSLCACertificateFile => settings.ssl_ca_file,  # 服务器可以要求客户端提供证书。使用服务器上的CA证书来验证客户端提供的证书,以确保双向验证。
        :SSLOptions => ssl_options,
        :SSLCiphers => CIPHERS - Proxy::SETTINGS.ssl_disabled_ciphers,
        :daemonize => false,
      }
    end

    def load_ssl_private_key(path)
      # 使用 File.read(path) 从指定路径读取私钥文件的内容，
      # 讀取指定的文件,并使用 OpenSSL::PKey::RSA.new 方法创建一个 OpenSSL::PKey::RSA 实例，表示一个 RSA 密钥对。
      OpenSSL::PKey::RSA.new(File.read(path))
    rescue Exception => e
      logger.error "Unable to load private SSL key. Are the values correct in settings.yml and do permissions allow reading?", e
      raise e
    end

    def load_ssl_certificate(path)
      # 读取指定路径的证书文件,来创建一个 X.509 证书对象
      OpenSSL::X509::Certificate.new(File.read(path))
    rescue Exception => e
      logger.error "Unable to load SSL certificate. Are the values correct in settings.yml and do permissions allow reading?", e
      raise e
    end

    # 依據 "pid_path"方法所返回的文件,檢查指定進程的狀態，並返回相應的符號（:exited、:dead、:running、:not_owned）表示該進程的狀態。
    def pid_status
      return :exited unless File.exist?(pid_path)  # 如果 pid_path 返回的文件不存在，則表示進程已經退出，直接返回 :exited。
      # 從 pid_path 文件中取得 pid(进程标识文件),通常以进程的名称或服务的名称命名,其中包含了与进程相关的信息，如进程的 PID 和其他运行时状态信息。
      pid = ::File.read(pid_path).to_i  
      return :dead if pid == 0
      #======================= Process.kill(signal, pid) 用於向指定的進程發送信號,以執行不同的操作。============================
      # signal 是要发送的信号的名称或编号。可以使用信号名称（如 "HUP"、"TERM"、"KILL" 等）或信号编号（如 1、9、15 等）。
      # 以下是一些常见的信号和它们的用途：
      #   HUP（1）：挂断信号，通常用于通知进程重新加载配置文件。
      #   INT（2）：中断信号，通常由用户发出的中断命令。
      #   QUIT（3）：退出信号，通常用于要求进程执行优雅退出。
      #   KILL（9）：终止信号，用于强制终止进程。
      #   TERM（15）：终止信号，用于请求进程正常终止。      
      # pid 是要接收信号的目标进程的进程ID。
      # 使用Process.kill发送信号可能需要适当的权限。发送KILL信号通常会终止进程，而发送TERM信号通常会请求进程正常退出。
      # 不同的信号可能会触发不同的处理程序，具体取决于目标进程的实现。
      #
      #****** INT, QUIT, KILL, TERM 等這些信號的作用有何差異? ******
      # INT (Interrupt) - 信号编号为 2。
      # 作用： 发送中断信号，通常由用户在终端按下 Ctrl + C 触发。这会导致程序终止。
      #
      # QUIT - 信号编号为 3。      
      # 作用： 发送退出信号，通常由用户在终端按下 Ctrl + \ 触发。类似于 INT 信号，但会导致程序生成 core dump 文件。
      #
      # KILL - 信号编号为 9。      
      # 作用： 发送强制终止信号，该信号无法被捕获、阻塞或忽略。使用 KILL 信号会立即终止进程，无论它正在执行什么操作。
      #
      # TERM (Terminate) - 信号编号为 15。      #
      # 作用： 发送终止信号，通常用于请求进程正常退出。与 KILL 不同，TERM 信号可以被进程捕获或忽略，进程在接收到 TERM 信号后有机会进行清理工作。
      #
      # 这些信号是 UNIX/Linux 操作系统中常见的进程管理工具，可以通过 kill 命令或编程语言中的相应 API 发送给进程。
      # 在编写程序时，可以通过信号处理机制来捕获并处理这些信号，以实现对程序的更好控制和管理。
      #====================================================================================================================

      # 發送"信號0"不会杀死进程,也不會對該進程做任何操作,只是會檢查該進程是否存在,若存在則返回true
      # 这种方法通常用于检查某个进程是否在运行，以便在必要时采取适当的操作。
      # 例如，在启动一个新的进程之前，可以使用这种方法检查同名的进程是否已经在运行，以避免重复启动相同的进程。      
      Process.kill(0, pid)  
        :running  # 表示正在執行
      rescue Errno::ESRCH  # 調用 Process.kill(0, pid) 時,若拋出了 Errno::ESRCH 異常，則表示進程不存在，返回 :dead。
        :dead
      rescue Errno::EPERM  # 調用 Process.kill(0, pid) 時,若拋出了 Errno::EPERM 異常，則表示當前用戶對該進程沒有權限，返回 :not_owned。
        :not_owned
    end

    def check_pid
      case pid_status
      when :running, :not_owned  # 如果进程已经在运行（:running 或 :not_owned），则输出错误日志并终止当前程序的执行，并设置退出状态码为 2；
        logger.error "A server is already running. Check #{pid_path}"
        exit(2)  # 使用 exit(2) 來終止程式的執行,並設置退出碼為2, 為什麼要終止呢? 大概是後面要創建一個新的,所以要終止舊的。
      when :dead  # 如果進程狀態是 :dead，表示進程已經死亡，則刪除 pid_path 文件。
        File.delete(pid_path)
      end
    end

    # 寫入進程ID（PID）到指定的 pid_path 文件中。
    def write_pid
      # FileUtils.mkdir_p 它接受一個目錄路徑作為參數，可以是絕對路徑或相對路徑。
      # 如果指定的目錄已經存在，則 mkdir_p 方法不執行任何操作。
      # 如果指定的目錄不存在，則 mkdir_p 方法會創建該目錄以及所有必要的父目錄。它會遞歸地創建父目錄，以確保所有的父目錄都存在。
      # File.dirname(pid_path): 如果 pid_path 是 "/path/to/some/file.txt"，那么 File.dirname(pid_path) 将返回 "/path/to/some"。
      # pid_path = File.expand_path(pid_path)  # 多了這個步驟,可以讓 "~/run/joseph/joseph_test.pid" 展開成絶對路徑。
      FileUtils.mkdir_p(File.dirname(pid_path)) unless File.exist?(pid_path)      
      # 打開指定的 pid_path 文件，並以創建模式（::File::CREAT）、獨占模式（::File::EXCL）和可寫模式（::File::WRONLY）打開該文件。
      # 然後，使用打開的文件對象 f，將當前進程的進程ID（Process.pid.to_s）寫入到該文件中。
      File.open(pid_path, ::File::CREAT | ::File::EXCL | ::File::WRONLY) { |f| f.write(Process.pid.to_s) }     
      at_exit { File.delete(pid_path) if File.exist?(pid_path) }   # at_exit 定義在程式結束時(整個 Ruby 程式的執行結束)要執行的塊（block）或方法。
    rescue Errno::EEXIST
      check_pid
      retry
    end

    def webrick_server(app, addresses, port)
      # 创建一个 WEBrick 的 HTTP 服务器对象，并将其赋值给变量 server,
      # 然後使用上述所產生的 "server对象" 来控制和配置 HTTP 服务器的行为。可以设置监听的端口、处理请求的应用程序、日志记录、SSL 设置等等。
      server = ::WEBrick::HTTPServer.new(app) 
      addresses.each { |address| server.listen(address, port) }  # address,用于指定服务器监听地址的参数,通常指的是服务器上的网络接口，而不是客户端的 IP 地址。
      # 若應用程序被掛載在 '/test'下,則只有以/test 为前缀的请求路径才会被匹配和传递给该应用程序处理。
      server.mount "/", Rack::Handler::WEBrick, app[:app]  # 将应用程序 app[:app] 挂载到 WEBrick 服务器的根路径（"/"）上。
      server
    end

    def launch
      logger.info("******** (1)Joesph say: Proxy::Launcher.launch 正在執行中 ... ***********")
      raise Exception.new("Both http and https are disabled, unable to start.") unless http_enabled? || https_enabled?  

      #if settings.daemon #該參數若為真,表示要創建一個 daemon
      #  check_pid
      #  Process.daemon  # 當它被呼叫時，當前的進程將變成一個守護進程，脫離控制終端並在後台運行,通常用於服務或守護程序。
      #  write_pid  # 将当前进程的PID写入文件中，通常称为PID文件。
      #end
      
      ::Proxy::PluginInitializer.new(::Proxy::Plugins.instance).initialize_plugins

      http_app = http_app(settings.http_port)
      https_app = https_app(settings.https_port)
      
      install_webrick_callback!(http_app, https_app)
     
      t1 = Thread.new { webrick_server(https_app, settings.bind_host, settings.https_port).start } unless https_app.nil?
      t2 = Thread.new { webrick_server(http_app, settings.bind_host, settings.http_port).start } unless http_app.nil?

      Proxy::SignalHandler.install_traps

      (t1 || t2).join  # 选择 t1 或 t2 中的一个线程，并等待选中的线程执行完成。这样可以确保在选择的线程执行完毕后再继续执行后续的代码。
    rescue SignalException => e
      logger.debug("Caught #{e}. Exiting")
      raise
    rescue SystemExit
      # do nothing. This is to prevent the exception handler below from catching SystemExit exceptions.
      raise
    rescue Exception => e
      logger.error "Error during startup, terminating", e
      puts "Errors detected on startup, see log for details. Exiting: #{e}"
      exit(1)    
    
    end

    # 用于协调多个 WEBrick 服务器的启动，确保所有的服务器都启动完成後再执行特定操作（在 launched(apps) 方法中定义）。
    def install_webrick_callback!(*apps)
      # compact! 是一个数组方法，用于移除数组中的所有 nil 元素，并返回修改后的数组。如果数组中没有 nil 元素，则返回 nil。
      # 如果你不希望改变原始数组，可以使用 compact 方法，它返回一个新的数组副本，而不影响原始数组。
      apps.compact!  

      # track how many webrick apps are still starting up
      @pending_webrick = apps.size
      # Mutex 是一种同步机制，它通过提供互斥访问来解决多线程环境中的竞态条件和数据竞争问题。
      # 使用 Mutex 可以保证同一时刻只有一个线程可以获得锁（即执行某段代码），而其他线程则必须等待锁的释放。
      @pending_webrick_lock = Mutex.new  

      apps.each do |app|     
        #==================================================================================================
        # :StartCallback 是 WEBrick::HTTPServer 的初始化参数之一，用于指定在服务器启动时执行的回调函数。
        # 当应用程序(应用程序所对应的 WEBrick 服务器)完成启动后，Systemd 将执行 :StartCallback 对应的回调函数。  
        # 当设置了 :StartCallback 参数时，它将指定一个在服务器启动时调用的块或 Proc。
        #  
        # 下面是一个简单的例子，演示如何使用 :StartCallback：  
        # 
        # 定义一个简单的 Rack 应用
        # app = Proc.new do |env|
        #   ['200', {'Content-Type' => 'text/plain'}, ['Hello, WEBrick!']]
        # end
        #
        # 创建 WEBrick 服务器
        # server = WEBrick::HTTPServer.new(
        #   :Port => 8080,
        #   :StartCallback => proc {
        #     # 在这个块内，你可以执行任何你希望在服务器启动时执行的逻辑。
        #     puts "Server is starting..."           
        #   }
        # )
        #
        # 挂载 Rack 应用
        # server.mount "/", Rack::Handler::WEBrick, app
        #
        # 启动服务器
        # server.start 
        #===================================================================================================      
        app[:StartCallback] = lambda do   # 在启动 WEBrick 实例时,将执行 :StartCallback 对应的回调函数。 
          # 通过调用 @pending_webrick_lock.synchronize 方法，确保只有一个线程能进入块内部的代码段中。其他线程会被阻塞，直到当前线程完成操作并释放锁。    
          @pending_webrick_lock.synchronize do
            @pending_webrick -= 1
            launched(apps) if @pending_webrick.zero?
          end
        end
      end
    end

    def launched(apps)
      logger.info("Smart proxy has launched on #{apps.size} socket(s), waiting for requests")
      # Systemd 是Linux 的始初化系統,負責在系統啟動時初始化各個系統,也提供了用于管理和监视服务的接口。
      # SdNotify.ready 是一个系统通知的功能，用於使一个服务或程序在启动过程中向 Systemd 发送一个 "已准备就绪" 的通知，表示该服务已经初始化完成，可以正常工作了。
      # 在 Ruby 程序中，当服务初始化完成后，可以调用 SdNotify.ready 方法发送通知。这对于 Systemd 来说，可以帮助它更好地管理服务的启动顺序和状态。
      # 请注意，要使用 SdNotify.ready 方法，首先需要安装 systemd_notify gem，并且运行环境需要支持 Systemd。
      # 这个功能主要用于在 Linux 系统中运行的服务或守护进程。在非 Systemd 环境下或非 Linux 系统中使用该方法是无效的。
      SdNotify.ready
    end


    def myputs               
      puts "***** 以下顯示 settings 的內容,我的測試 *****"
      @settings.each_pair do |key, value|
        puts "#{key}: #{value}"
      end
    end

  end
end