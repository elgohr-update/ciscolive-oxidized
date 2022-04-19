# frozen_string_literal: true

module Oxidized
  class CLI
    require "slop"
    require "oxidized"
    require "English"

    # 运行 oxidized
    def run
      check_pid
      Process.daemon if @options[:daemonize] || @options[:D]
      write_pid
      begin
        Oxidized.logger.info "Oxidized starting, running as pid #{$PROCESS_ID}"
        # 实例化对象
        Oxidized.new
      rescue StandardError => error
        crash error
        raise
      end
    end

    private
      def initialize
        _args, @options = parse_opts

        Config.load @options
        Oxidized.setup_logger

        @pidfile = File.expand_path(Oxidized.config.pid)
      end

      # 异常捕捉转储
      def crash(error)
        Oxidized.logger.fatal "Oxidized crashed, crash file written in #{Config::CRASH}"
        File.open Config::CRASH, "w" do |f|
          f.puts "-" * 50
          f.puts Time.now.utc
          f.puts error.message + " [" + error.class.to_s + "]"
          f.puts "-" * 50
          f.puts error.backtrace
          f.puts "-" * 50
        end
      end

      # oxidized 运行脚本参数解析
      def parse_opts
        opts = Slop.parse do |opt|
          opt.on "-d", "--debug", "turn on debugging"
          opt.on "-D", "--daemonize", "Daemonize/fork the process"
          opt.on "-s", "--show-exhaustive-config", "output entire configuration, including defaults" do
            asetus = Config.load
            puts asetus.to_yaml asetus.cfg
            Kernel.exit
          end
          opt.on "-h", "--help", "show usage" do
            puts opt
            Kernel.exit
          end
          opt.on "-v", "--version", "show version" do
            puts Oxidized::VERSION_FULL
            Kernel.exit
          end
        end
        [opts.arguments, opts]
      end

      attr_reader :pidfile

      def pidfile?
        !!pidfile
      end

      def write_pid
        return unless pidfile?

        begin
          File.open(pidfile, ::File::CREAT | ::File::EXCL | ::File::WRONLY) { |f| f.write(Process.pid.to_s) }
          at_exit { File.delete(pidfile) if File.exist?(pidfile) }
        rescue Errno::EEXIST
          check_pid
          retry
        end
      end

      def check_pid
        return unless pidfile?

        case pid_status(pidfile)
        when :running, :not_owned
          puts "A server is already running. Check #{pidfile}"
          exit(1)
        when :dead
          File.delete(pidfile)
        end
      end

      def pid_status(pidfile)
        return :exited unless File.exist?(pidfile)

        pid = ::File.read(pidfile).to_i
        return :dead if pid.zero?

        Process.kill(0, pid)
        :running
      rescue Errno::ESRCH
        :dead
      rescue Errno::EPERM
        :not_owned
      end
  end
end
