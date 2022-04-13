# frozen_string_literal: true

module Oxidized
  require "resolv"
  require "ostruct"
  require_relative "node/stats"

  class MethodNotFound < OxidizedError; end

  class ModelNotFound < OxidizedError; end

  class Node
    # 节点相关方法属性
    attr_reader :name, :ip, :model, :input, :output, :group, :auth, :prompt, :vars, :last, :repo
    attr_accessor :running, :user, :email, :msg, :from, :stats, :retry

    # 别名方法
    alias running? running

    def initialize(opt)
      Oxidized.logger.debug "resolving DNS for %s..." % opt[:name]
      # remove the prefix if an IP Address is provided with one as IPAddr converts it to a network address.
      ip_addr, = opt[:ip].to_s.split("/")
      Oxidized.logger.debug "IPADDR %s" % ip_addr.to_s
      @name = opt[:name]
      @ip = IPAddr.new(ip_addr).to_s rescue nil
      @ip     ||= Resolv.new.getaddress(@name) if Oxidized.config.resolve_dns?
      @ip     ||= @name
      @group  = opt[:group]
      @model  = resolve_model opt
      @input  = resolve_input opt
      @output = resolve_output opt
      @auth   = resolve_auth opt
      @prompt = resolve_prompt opt
      @vars   = opt[:vars]
      # 每个节点都有运行状态
      @stats = Stats.new
      @retry = 0
      @repo  = resolve_repo opt

      # model instance needs to access node instance
      @model.node = self
    end

    # 执行计划任务
    def run
      # 初始化变量
      status, config = :fail, nil

      @input.each do |input|
        # don't try input if model is missing config block, we may need strong config to class_name map
        cfg_name = input.to_s.split("::").last.downcase
        # 有假必假
        next unless @model.cfg[cfg_name] && (not @model.cfg[cfg_name].empty?)
        # 连续赋值：input 对象初始化并执行相关指令
        @model.input = input = input.new

        # 判断是否执行成功
        if (config = run_input(input))
          Oxidized.logger.debug "lib/oxidized/node.rb: #{input.class.name} ran for #{name} successfully"
          status = :success
          break
        else
          Oxidized.logger.debug "lib/oxidized/node.rb: #{input.class.name} failed for #{name}"
          status = :no_connection
        end
      end
      # 重置 input 属性
      @model.input = nil
      # 返回运行数据
      [status, config]
    end

    # 调度 input 方法
    def run_input(input)
      # 异常拦截
      rescue_fail = {}
      [input.class::RescueFail, input.class.superclass::RescueFail].each do |hash|
        hash.each do |level, errors|
          errors.each do |err|
            rescue_fail[err] = level
          end
        end
      end

      # 尝试联结设备并执行配置抓取，并做异常拦截
      begin
        input.connect(self) && input.get
      rescue *rescue_fail.keys => err
        resc = ""
        unless (level = rescue_fail[err.class])
          resc  = err.class.ancestors.find { |e| rescue_fail.has_key?(e) }
          level = rescue_fail[resc]
          resc  = " (rescued #{resc})"
        end
        Oxidized.logger.send(level, '%s raised %s%s with msg "%s"' % [ip, err.class, resc, err.message])
        false
      rescue StandardError => err
        crash_dir  = Oxidized.config.crash.directory
        crash_file = Oxidized.config.crash.hostname? ? name : ip.to_s
        FileUtils.mkdir_p(crash_dir) unless File.directory?(crash_dir)

        # 异常日志转储
        File.open File.join(crash_dir, crash_file), "w" do |fh|
          fh.puts Time.now.utc
          fh.puts err.message + " [" + err.class.to_s + "]"
          fh.puts "-" * 50
          fh.puts err.backtrace
          fh.puts "-" * 50
        end
        Oxidized.logger.error '%s raised %s with msg "%s", %s saved' % [ip, err.class, err.message, crash_file]
        false
      end
    end

    # 对象参数序列化
    def serialize
      h             = {
        name:      @name,
        full_name: @name,
        ip:        @ip,
        group:     @group,
        model:     @model.class.to_s,
        last:      nil,
        vars:      @vars,
        mtime:     @stats.mtime
      }
      h[:full_name] = [@group, @name].join("/") if @group
      if @last
        h[:last] = {
          start:  @last.start,
          end:    @last.end,
          status: @last.status,
          time:   @last.time
        }
      end
      h
    end

    # 加载最近备份状态
    def last=(job)
      if job
        ostruct = OpenStruct.new
        # 提前最近状态相关数据
        ostruct.start  = job.start
        ostruct.end    = job.end
        ostruct.status = job.status
        ostruct.time   = job.time
        @last          = ostruct
      else
        @last = nil
      end
    end

    # 重置相关变量
    def reset
      @user  = @email = @msg = @from = nil
      @retry = 0
    end

    # 设置修改时间
    def modified
      @stats.update_mtime
    end

    private
      def resolve_prompt(opt)
        # 解析设备成功登录提示符：搜索路径 -> 设备自定义、模块以及全局配置
        opt[:prompt] || @model.prompt || Oxidized.config.prompt
      end

      # 检查节点权限账号密码
      def resolve_auth(opt)
        {
          username: resolve_key(:username, opt),
          password: resolve_key(:password, opt)
        }
      end

      # 解析节点 Input 方法
      def resolve_input(opt)
        inputs = resolve_key :input, opt, Oxidized.config.input.default
        inputs.split(/\s*,\s*/).map do |input|
          # 动态加载模块，非无脑全量加载
          unless Oxidized.mgr.input[input]
            Oxidized.logger.debug "lib/oxidized/node.rb: Loading output #{input.inspect}"
            Oxidized.mgr.add_input(input) || raise(MethodNotFound, "#{input} not found for node #{ip}")
          end
          Oxidized.mgr.input[input]
        end
      end

      # 解析节点 Output 方法
      def resolve_output(opt)
        output = resolve_key :output, opt, Oxidized.config.output.default
        # 动态加载模块，非无脑全量加载
        unless Oxidized.mgr.output[output]
          Oxidized.logger.debug "lib/oxidized/node.rb: Loading output #{output.inspect}"
          Oxidized.mgr.add_output(output) || raise(MethodNotFound, "#{output} not found for node #{ip}")
        end
        Oxidized.mgr.output[output]
      end

      # 解析节点模块
      def resolve_model(opt)
        model = resolve_key :model, opt
        # 动态加载模块，非无脑全量加载
        unless Oxidized.mgr.model[model]
          Oxidized.logger.debug "lib/oxidized/node.rb: Loading model #{model.inspect}"
          Oxidized.mgr.add_model(model) || raise(ModelNotFound, "#{model} not found for node #{ip}")
        end
        # 加载后实例化类对象
        Oxidized.mgr.model[model].new
      end

      # 解析版本控制仓库地址
      def resolve_repo(opt)
        type = git_type opt
        return nil unless type

        remote_repo = Oxidized.config.output.send(type).repo
        if remote_repo.is_a?(::String)
          if Oxidized.config.output.send(type).single_repo? || @group.nil?
            remote_repo
          else
            File.join(File.dirname(remote_repo), @group + ".git")
          end
        else
          remote_repo[@group]
        end
      end

      def resolve_key(key, opt, global = nil)
        # 优先解析全局配置、属组配置，最后为节点自定义配置
        key_sym = key.to_sym
        key_str = key.to_s
        value   = global
        Oxidized.logger.debug "node.rb: resolving node key '#{key}', with passed global value of '#{value}' and node value '#{opt[key_sym]}'"

        # 未定义全局配置的情况下，检查全局配置属性
        if (not value) && Oxidized.config.has_key?(key_str)
          value = Oxidized.config[key_str]
          Oxidized.logger.debug "node.rb: setting node key '#{key}' to value '#{value}' from global"
        end

        # 属组配置解析
        if Oxidized.config.groups.has_key?(@group)
          if Oxidized.config.groups[@group].has_key?(key_str)
            value = Oxidized.config.groups[@group][key_str]
            Oxidized.logger.debug "node.rb: setting node key '#{key}' to value '#{value}' from group"
          end
        end

        # 模块配置解析
        model_name = @model.class.name.to_s.downcase
        if Oxidized.config.models.has_key? model_name
          if Oxidized.config.models[model_name].has_key?(key_str)
            value = Oxidized.config.models[model_name][key_str]
            Oxidized.logger.debug "node.rb: setting node key '#{key}' to value '#{value}' from model"
          end
        end

        # 节点配置解析
        value = opt[key_sym] || value
        Oxidized.logger.debug "node.rb: returning node key '#{key}' with value '#{value}'"
        value
      end

      def git_type(opt)
        type = opt[:output] || Oxidized.config.output.default
        return nil unless type[0..2] == "git"
        type
      end
  end
end
