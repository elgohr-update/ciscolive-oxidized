# frozen_string_literal: true

module Oxidized
  class Http < Output
    attr_reader :commitref

    # 初始化入口
    def initialize
      @cfg = Oxidized.config.output.http
    end

    # 设置缺省数据
    def setup
      return unless @cfg.empty?

      CFGS.user.output.http.user    = "Netstack"
      CFGS.user.output.http.pasword = "secret"
      CFGS.user.output.http.url     = "http://localhost/web-api/netstack"
      CFGS.save :user
      raise NoConfig, "no output http config, edit ~/.config/oxidized/config"
    end

    # 注入依赖
    require "net/http"
    require "uri"
    require "json"

    # 节点快照转储
    def store(node, outputs, opt = {})
      @commitref = nil
      uri        = URI.parse @cfg.url
      http       = Net::HTTP.new uri.host, uri.port
      # http.use_ssl = true if uri.scheme = 'https'
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      req.basic_auth @cfg.user, @cfg.password
      req.body = generate_json(node, outputs, opt)
      response = http.request req

      # 解析 HTTP RESPONSE
      case response.code.to_i
      when 200 || 201
        Oxidized.logger.info "Configuration http backup complete for #{node}"
        p [:success]
      when (400..499)
        Oxidized.logger.info "Configuration http backup for #{node} failed status: #{response.body}"
        p [:bad_request]
      when (500..599)
        p [:server_problems]
        Oxidized.logger.info "Configuration http backup for #{node} failed status: #{response.body}"
      end
    end

    private
      def generate_json(node, outputs, opt)
        # actually we need to also iterate outputs, for other types like in gitlab.
        # But most people don't use 'type' functionality.
        JSON.pretty_generate(
          "msg"    => opt[:msg],
          "user"   => opt[:user],
          "email"  => opt[:email],
          "group"  => opt[:group],
          "node"   => node,
          "config" => outputs.to_cfg
        )
      end
  end
end
