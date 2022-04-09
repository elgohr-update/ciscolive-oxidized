# frozen_string_literal: true

module Oxidized
  class Input
    module CLI
      attr_reader :node

      def initialize
        @post_login = []
        @pre_logout = []
        # 初始化账号密码、执行类
        @username, @password, @exec = nil
      end

      # 节点配置快照入口
      def get
        connect_cli
        d = node.model.get
        disconnect
        d
      rescue PromptUndetect
        disconnect
        raise
      end

      # 连接设备节点
      def connect_cli
        Oxidized.logger.debug "lib/oxidized/input/cli.rb: Running post_login commands at #{node.name}"
        @post_login.each do |command, block|
          Oxidized.logger.debug "lib/oxidized/input/cli.rb: Running post_login command: #{command.inspect}, block: #{block.inspect} at #{node.name}"
          block ? block.call : (cmd command)
        end
      end

      # 登出设备节点
      def disconnect_cli
        Oxidized.logger.debug "lib/oxidized/input/cli.rb Running pre_logout commands at #{node.name}"
        @pre_logout.each do |command, block|
          Oxidized.logger.debug "lib/oxidized/input/cli.rb: Running pre_logout command: #{command.inspect}, block: #{block.inspect} at #{node.name}"
          block ? block.call : (cmd command)
        end
      end

      # 登录之后回调钩子
      def post_login(cmd = nil, &block)
        return if @exec
        @post_login << [cmd, block]
      end

      # 登出之前回调钩子
      def pre_logout(cmd = nil, &block)
        return if @exec
        @pre_logout << [cmd, block]
      end

      def username(regex = /^(Username|login)/i)
        @username ||= regex
      end

      def password(regex = /^Password/i)
        @password ||= regex
      end

      # 节点登录函数入口
      def login
        # 正则表达式列表
        match_re = [@node.prompt]
        match_re << @username if @username
        match_re << @password if @password
        # 一直运行到条件表达式为真，如果失败则超时异常
        until (match = expect(match_re)) == @node.prompt
          cmd(@node.auth[:username], nil) if match == @username
          cmd(@node.auth[:password], nil) if match == @password
          match_re.delete match
        end
      end
    end
  end
end
