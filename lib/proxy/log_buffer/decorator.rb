require 'proxy/log_buffer/buffer'

module Proxy::LogBuffer
  class Decorator
    def self.instance
      @@instance ||= new(::Proxy::LoggerFactory.logger, ::Proxy::LoggerFactory.log_file) 
    end    

    def initialize(logger, log_file, buffer = Proxy::LogBuffer::Buffer.instance)   
      @logger = logger
      @log_file = log_file
      @buffer = buffer
      @mutex = Mutex.new
      # self.roll_log = false; 这样做会调用对象的 attr_accessor 自动生成的 setter 方法，将值赋给实例变量 @roll_log。
      # 或是, @roll_log = false, 直接賦值給 @roll_log
      # 若是 roll_log = false, 則 roll_log 會被視為方法的局變,離開此方法的控制域就會消失,
      self.roll_log = false  
    end

    attr_accessor :formatter, :roll_log
    alias_method :roll_log?, :roll_log  # alias_method :new_method_name, :existing_method_name 允许为一个已存在的方法创建一个别名

    def add(severity, message = nil, progname = nil, exception_or_backtrace = nil)
      severity ||= UNKNOWN      
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
        end
      end
      message = formatter.call(severity, Time.now.utc, progname, message) if formatter
      return if message == ''

      reopened = false
      @mutex.synchronize do
        if roll_log?
          # decorator is in-memory only, reopen underlaying logging appenders
          # ::Logging.reopen 是 Logging gem 提供的方法,用于重新打开日志文件以实现日志滚动（rolling）或 重新配置日志记录。
          # 当需要执行日志滚动（rolling）时，通常会调用 ::Logging.reopen 方法，根据一些条件(日期,文件大小...)切割日志,
          # 它会关闭当前的日志文件，然后重新打开一个新的日志文件,以便将新的日志记录进入新的日志文件。
          ::Logging.reopen  
          self.roll_log = false  # 類似開關,是为了控制滚动日志文件的行为。
          reopened = true  # 记录是否已重新打开日志文件的状态。
        end        
        @logger.add(severity, message) 
        if severity >= @logger.level
            # exception_or_backtrace.is_a?(Exception), 判斷 exception_or_backtrace對象是不是 Exception 类的实例,或者是其子类的实例。
            backtrace = if exception_or_backtrace.is_a?(Exception) && !exception_or_backtrace.backtrace.nil?  # exception_or_backtrace.present?
                          exception_or_backtrace.message + ': ' + exception_or_backtrace.backtrace.join("\n")
                        #=========================================================================================================
                        # (1) 检查 backtrace 变量是否有 join 方法，如果有，则意味着 backtrace 可以被连接成一个字符串。
                        # (2) backtrace 变量在进入条件块之前还没有被赋值，因此它的初始值是 nil。
                        #     但是，elsif backtrace.respond_to?(:join) 仍然是合法的，因为在 Ruby 中，nil 对象也具有 respond_to? 方法。
                        #     然而,我覺得還是修改為 elsif exception_or_backtrace.respond_to?(:join) 比較合理。
                        #=========================================================================================================   
                        # elsif backtrace.respond_to?(:join)                                        
                        elsif exception_or_backtrace.respond_to?(:backtrace) && exception_or_backtrace.backtrace.respond_to?(:join)
                            exception_or_backtrace.backtrace.join("\n")
                        else
                            exception_or_backtrace
                        end
          rec = Proxy::LogBuffer::LogRecord.new(nil, severity, message.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?'), backtrace, request_id)
          @buffer.push(rec)
        end 

      end
      info("Logging file reopened via USR1 signal") if reopened
      # exceptions are also sent to structured log if available
      # "exception_or_backtrace&.is_a?(Exception)"; 判斷 exception_or_backtrace 是否是 Exception 類或其子類。
      exception("Error details for #{message}", exception_or_backtrace) if exception_or_backtrace&.is_a?(Exception)
    end

    def trace?
      @trace ||= !!ENV['FOREMAN_PROXY_TRACE']
    end
  
    def trace(msg_or_progname = nil, exception_or_backtrace = nil, &block)
      add(::Logger::Severity::DEBUG, nil, msg_or_progname, exception_or_backtrace, &block) if trace?
    end
  
    def debug(msg_or_progname = nil, exception_or_backtrace = nil, &block)
      add(::Logger::Severity::DEBUG, nil, msg_or_progname, exception_or_backtrace, &block)
    end
  
    def info(msg_or_progname = nil, exception_or_backtrace = nil, &block)
      add(::Logger::Severity::INFO, nil, msg_or_progname, exception_or_backtrace, &block)
    end
    alias_method :write, :info
  
    def warn(msg_or_progname = nil, exception_or_backtrace = nil, &block)
      add(::Logger::Severity::WARN, nil, msg_or_progname, exception_or_backtrace, &block)
    end
    alias_method :warning, :warn
  
    def error(msg_or_progname = nil, exception_or_backtrace = nil, &block)
      add(::Logger::Severity::ERROR, nil, msg_or_progname, exception_or_backtrace, &block)
    end
  
    def fatal(msg_or_progname = nil, exception_or_backtrace = nil, &block)
      add(::Logger::Severity::FATAL, nil, msg_or_progname, exception_or_backtrace, &block)
    end
  
    def request_id
      (r = ::Logging.mdc['request']).nil? ? r : r.to_s[0..7]
    end
        
    def with_fields(fields = {})   
      # 下列的作法有問題; Logging.mdc.push 方法好像對塊沒有反應,不會執行塊中的代碼      
      ::Logging.mdc.push(fields) do 
        yield    
      end
    end

    def with_fields_joseph(fields = {})
      begin
        # 在mdc中添加的 hash,可以通過 Logging.layouts.pattern 的設置,添加到日志中。
        ::Logging.mdc.push(fields)   # mdc的說明,請看注記(1)
        yield  # yield 用于执行传递给方法的块。
      ensure
        ::Logging.mdc.pop
      end
    end

    def exception(context_message, exception, options = {})
      level = options[:level] || :warn
      # ::Logging::LEVELS 是一个哈希表，它将日志级别名称映射到其对应的整数值。例如，'INFO' 映射到 1，'WARN' 映射到 2，等等。
      # ::Logging::LEVELS.key?(level.to_s) 表示检查 level.to_s 是否存在于::Logging::LEVELS 的键集合中。
      unless ::Logging::LEVELS.key?(level.to_s)
        raise "Unexpected log level #{level}, expected one of #{::Logging::LEVELS.keys}"
      end
      # send class, message and stack as structured fields in addition to message string
      backtrace = exception.backtrace || []
      extra_fields = {
        exception_class: exception.class.name,
        exception_message: exception.message,
        exception_backtrace: backtrace,
      }
      extra_fields[:foreman_code] = exception.code if exception.respond_to?(:code)  # 检查 exception 对象是否有定義 code 方法。

      with_fields_joseph(extra_fields) do   # fn(a) {...}; fn方法接受一个参数 a，後面跟著一個塊，塊內的代码将在 fn 方法内部执行。
        # 动态调用对象的公共（public）方法，类似于 send 方法。
        # 但与 send 不同，public_send 只能调用对象的公共方法，不能调用私有（private）方法或受保护（protected）方法。
        # 被調用的方法名称由 level 参数决定，例如，如果 level 是 :debug，那么就会调用 debug 方法。
        # public_send 后面附加一个块时，这个块会被传递给"被调用的方法"(是由level參數決定的方法,而不是public_send)作为方法的参数。
        # 这里的 do ... end 块会被传递给由 level 决定的日志方法。具体来说，它会被传递给某个日志方法，例如 debug、info、warn 等。
        # 在方法内部，这个块会被执行，生成一条日志消息的内容。然后，这个内容会被传递给日志方法，用于记录日志。块的执行结果就是日志消息的内容。
        public_send(level) do           
          (["#{context_message}: <#{exception.class}>: #{exception.message}"] + backtrace).join("\n")
        end
      end
    end

    # method_missing 方法用于处理在对象上调用不存在的方法时的行为。
    # 当对象上调用一个不存在的方法时，Ruby 会自动调用 method_missing 方法，
    # 并将调用的方法名（symbol）以及传递给该方法的参数(*args)传递给 method_missing 方法。    
    def method_missing(symbol, *args)
      @logger.send(symbol, *args)
    end  

  end
end

=begin 
  # ********* (1) mdc(Mapped Diagnostic Context)才能支持hsah,ndc(Nested Diagnostic Context)只能支持字符串 **********
  require 'logging'
  logger = Logging.logger['mylogger']
  appender = Logging.appenders.stdout

  #******* MDC(Mapped Diagnostic Context)才能支持hsah **********
  pattern1 = '%d %c %l --abc: %X{abc}, xyz: %X{xyz}-- %m\n'
  appender.layout = Logging.layouts.pattern(
     :pattern => pattern1,
     :color_scheme => 'default'
   )
  logger.add_appenders(appender)

  Logging.mdc.clear
  fields = {:abc => "ABC", :xyz => "XYZ"}
  Logging.mdc.push(:abc => "ABC", :xyz => "XYZ")
  logger.info('This is an info message with NDC')

  #******* ndc(Nested Diagnostic Context)只能支持字符串 *******
  pattern2 = '%d %c -%x-  %m'
  appender.layout = Logging.layouts.pattern(
     :pattern => pattern2,
     :color_scheme => 'default'
   )
  logger.add_appenders(appender)

  Logging.ndc.clear
  Logging.ndc.push('SomeContext')
  logger.info('This is an info message with NDC')
=end
