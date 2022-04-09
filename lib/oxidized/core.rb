# frozen_string_literal: true

module Oxidized
  # 模块单例方法
  class << self
    def new(*args)
      Core.new args
    end
  end

  class Core
    class NoNodesFound < OxidizedError; end

    def initialize(_args)
      # 加载模块、类
      Oxidized.mgr = Manager.new
      # 钩子函数
      Oxidized.hooks = HookManager.from_config(Oxidized.config)
      # 加载设备清单
      nodes = Nodes.new
      raise NoNodesFound, "source returns no usable nodes" if nodes.size.zero?

      # 初始化工作队列
      @worker = Worker.new nodes
      trap("HUP") { nodes.load }
      if Oxidized.config.rest?
        begin
          require "oxidized/web"
        rescue LoadError
          raise OxidizedError, 'oxidized-web not found: sudo gem install oxidized-web - \
          or disable web support by setting "rest: false" in your configuration'
        end
        @rest = API::Web.new nodes, Oxidized.config.rest
        @rest.run
      end
      run
    end

    private
      def run
        Oxidized.logger.debug "lib/oxidized/core.rb: Starting the worker..."
        @worker.work while sleep Config::SLEEP
      end
  end
end
