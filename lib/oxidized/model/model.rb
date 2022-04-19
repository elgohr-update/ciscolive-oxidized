require "strscan"
require_relative "outputs"

module Oxidized
  class Model
    include Oxidized::Config::Vars

    # 类方法属性
    # 继承该类自动会具备类方法
    class << self
      # 模块继承
      def inherited(klass)
        if klass.superclass == Oxidized::Model
          klass.instance_variable_set "@cmd", Hash.new { |h, k| h[k] = [] }
          klass.instance_variable_set "@cfg", Hash.new { |h, k| h[k] = [] }
          klass.instance_variable_set "@procs", Hash.new { |h, k| h[k] = [] }
          klass.instance_variable_set "@expect", []
          klass.instance_variable_set "@comment", nil
          klass.instance_variable_set "@prompt", nil
        else
          # we're subclassing some existing model, take its variables
          instance_variables.each do |var|
            klass.instance_variable_set var, instance_variable_get(var)
          end
        end
      end

      # 配置批注
      def comment(str = "# ")
        if block_given?
          @comment = yield str
        elsif not @comment
          @comment = str
        else
          @comment
        end
      end

      # 设置登录提示符 @prompt 字串
      def prompt(regex = nil)
        # regex = Regexp.new(regex) unless regex.class == Regexp
        @prompt = regex || @prompt
      end

      # 设置 cfg 配置到 @cfg HASH 容器
      def cfg(*methods, **args, &block)
        [methods].flatten.each do |method|
          # 向 @cfg[method] 添加代码块处理逻辑
          # 成功登录设备后，登出设备之前节点设置钩子函数
          process_args_block(@cfg[method.to_s], args, block)
        end
      end

      # 节点运行配置 HASH
      def cfgs
        @cfg
      end

      # 设置执行脚本到 @cmd HASH 容器
      def cmd(cmd_arg = nil, **args, &block)
        # 检查是否为符号类型，随后向 @cmd 追加代码块处理逻辑
        if cmd_arg.class == Symbol
          process_args_block(@cmd[cmd_arg], args, block)
        else
          process_args_block(@cmd[:cmd], args, [cmd_arg, block])
        end
        Oxidized.logger.debug "lib/oxidized/model/model.rb Added #{cmd_arg} to the commands list"
      end

      # 节点相关的命令行 HASH
      def cmds
        @cmd
      end

      # 设置模型正则表达式处理逻辑保存到 @expect Array 属性
      def expect(regex, **args, &block)
        # 添加正则表达式规则到 @expect 列表
        process_args_block(@expect, args, [regex, block])
      end

      # 节点相关的正则表达式 Array
      def expects
        @expect
      end

      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @return [Hash] hash proc procs :pre+:post to be prepended/postfixed to output
      attr_reader :procs

      # calls the block at the end of the model, prepending the output of the
      # block to the output string
      #
      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @yield expects block which should return [String]
      # @return [void]
      def pre(**args, &block)
        # 向 @procs[:pre] 中追加代码块处理逻辑
        process_args_block(@procs[:pre], args, block)
      end

      # calls the block at the end of the model, adding the output of the block
      # to the output string
      #
      # @author Saku Ytti <saku@ytti.fi>
      # @since 0.0.39
      # @yield expects block which should return [String]
      # @return [void]
      def post(**args, &block)
        # 向 @procs[:post] 中追加代码块处理逻辑
        process_args_block(@procs[:post], args, block)
      end

      private
        def process_args_block(target, args, block)
          # 向特定属性追加元素，均为数组形式 | Array
          if args[:clear]
            target.replace([block])
          else
            method = args[:prepend] ? :unshift : :push
            target.send(method, block)
          end
        end
    end

    # 类对象属性：设备登录方法【TELNET SSH HTTP HTTPS】，具体节点信息
    attr_accessor :input, :node

    # 执行脚本并关联代码块函数
    def cmd(string, &block)
      Oxidized.logger.debug "lib/oxidized/model/model.rb Executing #{string}"
      # 具体的登录方式下执行脚本，并做早期异常拦截
      out = @input.cmd(string)
      return false unless out

      # 是否需要 UTF8编码、全局配置处理以及移除敏感信息
      out = out.b unless Oxidized.config.input.utf8_encoded?
      self.class.cmds[:all].each do |all_block|
        # 传递变量给实例对象，同时执行回调函数
        out = instance_exec Oxidized::String.new(out), string, &all_block
      end
      if vars :remove_secret
        self.class.cmds[:secret].each do |all_block|
          # 传递变量给实例对象，同时执行回调函数
          out = instance_exec Oxidized::String.new(out), string, &all_block
        end
      end

      # 将脚本输出字串转换为 Oxidized::String，方便调用部分方法
      # 传递变量给实例对象，同时执行回调函数
      out = instance_exec Oxidized::String.new(out), &block if block
      process_cmd_output out, string
    end

    # 配置转储形式：文本、GIT等，此处打印执行结果
    def output
      @input.output
    end

    # 节点登录设备方式，执行配置下发
    def send(data)
      # 设备登录方法必须实现 send method
      @input.send data
    end

    # 向 @expect 属性追加正则表达式处理逻辑
    def expect(regex, &block)
      self.class.expect regex, &block
    end

    # 节点相关的配置快照
    def cfg
      self.class.cfgs
    end

    # 节点模块成功登录提示符
    def prompt
      self.class.prompt
    end

    # 正则表达式捕捉并执行回调
    def expects(data)
      self.class.expects.each do |re, cb|
        # 实例化的对象接收数据，执行回调函数。其中 arity 动态判断需要接收几个参数
        # instance_exec 实例化对象接收参数并执行代码块，其结果返回给 data
        if data.match? re
          # 检查回调函数入参是否刚好为 2
          data = (cb.arity == 2) ? instance_exec([data, re], &cb) : instance_exec(data, &cb)
        end
      end
      # 兜底返回
      data
    end

    # 节点关联模板执行快照抓取
    def get
      Oxidized.logger.debug "lib/oxidized/model/model.rb Collecting commands' outputs"
      outputs = Outputs.new
      procs   = self.class.procs

      # 依次执行 cmd 脚本
      self.class.cmds[:cmd].each do |command, block|
        # @input cmd 方法 隐式调用匹配到 @prompt
        out = cmd command, &block
        return false unless out
        outputs << out
      end
      # 登出设备前执行回调函数
      procs[:pre].each do |pre_proc|
        outputs.unshift process_cmd_output(instance_eval(&pre_proc), "")
      end
      # 登录设备后执行回调函数
      procs[:post].each do |post_proc|
        outputs << process_cmd_output(instance_eval(&post_proc), "")
      end
      outputs
    end

    # 为每一行脚本添加注释符
    def comment(str)
      data = ""
      str.each_line do |line|
        data << self.class.comment << line
      end
      data
    end

    def xml_comment(str)
      # XML Comments start with <!-- and end with -->
      #
      # Because it's illegal for the first or last characters of a comment
      # to be a -, i.e. <!--- or ---> are illegal, and also to improve
      # readability, we add extra spaces after and before the beginning
      # and end of comment markers.
      #
      # Also, XML Comments must not contain --. So we put a space between
      # any double hyphens, by replacing any - that is followed by another -
      # with '- '
      data = ""
      str.each_line do |line|
        data << "<!-- " << line.gsub(/-(?=-)/, "- ").chomp << " -->\n"
      end
      data
    end

    def screen_scrape
      @input.class.to_s.match?(/Telnet/) || vars(:ssh_no_exec)
    end

    private
      def process_cmd_output(output, name)
        output = Oxidized::String.new(output) if output.is_a?(::String)
        output = Oxidized::String.new("") unless output.instance_of?(Oxidized::String)
        output.set_cmd(name)
        output
      end
  end
end
