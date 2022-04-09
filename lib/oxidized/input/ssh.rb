module Oxidized
  require "net/ssh"
  require "net/ssh/proxy/command"
  require "timeout"
  require_relative "cli"

  class SSH < Input
    include Input::CLI

    RescueFail = {
      debug: [
               Net::SSH::Disconnect
             ],
      warn:  [
               RuntimeError,
               Net::SSH::AuthenticationFailed
             ]
    }.freeze

    class NoShell < OxidizedError; end

    def connect(node)
      @node        = node
      @output      = ""
      @pty_options = { term: "vt100" }
      @node.model.cfg["ssh"].each { |cb| instance_exec(&cb) }
      @log = File.open(Oxidized::Config::LOG + "/#{@node.ip}-ssh", "w") if Oxidized.config.input.debug?
      Oxidized.logger.debug "lib/oxidized/input/ssh.rb: Connecting to #{@node.name}"

      # 初始化 SSH 对象
      @ssh = Net::SSH.start(@node.ip, @node.auth[:username], make_ssh_opts)
      unless @exec
        shell_open @ssh
        begin
          login
        rescue Timeout::Error
          raise PromptUndetect, [@output, "not matching configured prompt", @node.prompt].join(" ")
        end
      end
      connected?
    end

    # 检查设备是否已经连接
    def connected?
      @ssh && (not @ssh.closed?)
    end

    # 执行 SSH 命令下发
    def cmd(cmd, expect = node.prompt)
      Oxidized.logger.debug "lib/oxidized/input/ssh.rb #{cmd} @ #{node.name} with expect: #{expect.inspect}"
      if @exec
        @ssh.exec! cmd
      else
        cmd_shell(cmd, expect).gsub(/\r\n/, "\n")
      end
    end

    # 执行脚本
    def send(data)
      @ses.send_data data
    end

    attr_reader :output

    def pty_options(hash)
      @pty_options = @pty_options.merge hash
    end

    private
      def disconnect
        disconnect_cli
        # if disconnect does not disconnect us, give up after timeout
        Timeout.timeout(Oxidized.config.timeout) { @ssh.loop }
      rescue Errno::ECONNRESET, Net::SSH::Disconnect, IOError
      ensure
        @log.close if Oxidized.config.input.debug?
        (@ssh.close rescue true) unless @ssh.closed?
      end

      # 开启 SSH_CHANNEL
      def shell_open(ssh)
        @ses = ssh.open_channel do |ch|
          # 打印并保存数据
          ch.on_data do |_ch, data|
            if Oxidized.config.input.debug?
              @log.print data
              @log.flush
            end
            # 数据持久化以及字串修正
            @output << data
            @output = @node.model.expects @output
          end
          # 请求 PTY_CHANNEL
          ch.request_pty(@pty_options) do |_ch, success_pty|
            raise NoShell, "Can't get PTY" unless success_pty

            ch.send_channel_request "shell" do |_ch, success_shell|
              raise NoShell, "Can't get shell" unless success_shell
            end
          end
        end
      end

      # exec 属性
      def exec(state = nil)
        return nil if vars(:ssh_no_exec)

        state.nil? ? @exec : (@exec = state)
      end

      # 执行脚本推送
      def cmd_shell(cmd, expect_re)
        @output = ""
        @ses.send_data "#{cmd}\n"
        @ses.process
        expect expect_re if expect_re

        @output
      end

      # 捕捉 SSH 会话输出脚本
      def expect(*regexps)
        regexps = [regexps].flatten
        Oxidized.logger.debug "lib/oxidized/input/ssh.rb: expecting #{regexps.inspect} at #{node.name}"

        # 开启计时器，执行代码块
        Timeout.timeout(Oxidized.config.timeout) do
          # ssh 会话一直运行到代码块返回 false
          @ssh.loop(0.1) do
            sleep 0.1
            match = regexps.find { |regexp| @output.match regexp }
            return match if match
            true
          end
        end
      end

      # 初始化 SSH 会话相关参数
      def make_ssh_opts
        secure   = Oxidized.config.input.ssh.secure?
        ssh_opts = {
          number_of_password_prompts: 0,
          keepalive:                  vars(:ssh_no_keepalive) ? false : true,
          verify_host_key:            secure ? :always : :never,
          password:                   @node.auth[:password],
          timeout:                    Oxidized.config.timeout,
          port:                       (vars(:ssh_port) || 22).to_i
        }

        auth_methods            = vars(:auth_methods) || %w[none password publickey]
        ssh_opts[:auth_methods] = auth_methods
        Oxidized.logger.debug "AUTH METHODS::#{auth_methods}"

        ssh_opts[:proxy]      = make_ssh_proxy_command(vars(:ssh_proxy), vars(:ssh_proxy_port), secure) if vars(:ssh_proxy)

        ssh_opts[:keys]       = [vars(:ssh_keys)].flatten if vars(:ssh_keys)
        ssh_opts[:kex]        = vars(:ssh_kex).split(/,\s*/) if vars(:ssh_kex)
        ssh_opts[:encryption] = vars(:ssh_encryption).split(/,\s*/) if vars(:ssh_encryption)
        ssh_opts[:host_key]   = vars(:ssh_host_key).split(/,\s*/) if vars(:ssh_host_key)
        ssh_opts[:hmac]       = vars(:ssh_hmac).split(/,\s*/) if vars(:ssh_hmac)

        if Oxidized.config.input.debug?
          ssh_opts[:logger]  = Oxidized.logger
          ssh_opts[:verbose] = Logger::DEBUG
        end

        ssh_opts
      end

      # 初始化 SSH_PROXY 相关参数
      def make_ssh_proxy_command(proxy_host, proxy_port, secure)
        return nil unless !proxy_host.nil? && !proxy_host.empty?

        proxy_command = "ssh "
        proxy_command += "-o StrictHostKeyChecking=no " unless secure
        proxy_command += "-p #{proxy_port} " if proxy_port
        proxy_command += "#{proxy_host} -W [%h]:%p"
        Net::SSH::Proxy::Command.new(proxy_command)
      end
  end
end
