# frozen_string_literal: true

module Oxidized
  class Job < Thread
    attr_reader :start, :end, :status, :time, :node, :config

    def initialize(node)
      @node  = node
      @start = Time.now.utc
      super do
        Oxidized.logger.debug "lib/oxidized/job.rb: Starting fetching process for #{@node.name} at #{Time.now.utc}"
        # 运行节点任务，返回状态和相关配置
        @status, @config = @node.run
        @end             = Time.now.utc
        @time            = @end - @start
        Oxidized.logger.debug "lib/oxidized/job.rb: Config fetched for #{@node.name} at #{@end}"
      end
    end
  end
end
