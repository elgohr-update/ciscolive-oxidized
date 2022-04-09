# frozen_string_literal: true

module Oxidized
  require_relative "job"
  require_relative "jobs"

  class Worker
    # 初始化入口
    def initialize(nodes)
      @jobs_done  = 0
      @nodes      = nodes
      @jobs       = Jobs.new(Oxidized.config.threads, Oxidized.config.interval, @nodes)
      @nodes.jobs = @jobs
      # 异常直接终止
      Thread.abort_on_exception = true
    end

    # 调度任务
    def work
      ended = []
      @jobs.delete_if { |job| ended << job unless job.alive? }
      ended.each { |job| process job }

      @jobs.work
      while @jobs.size < @jobs.want
        Oxidized.logger.debug "lib/oxidized/worker.rb: Jobs running: #{@jobs.size} of #{@jobs.want} - ended: #{@jobs_done} of #{@nodes.size}"
        # ask for next node in queue non destructive way
        next_node = @nodes.first
        unless next_node.last.nil?
          # Set unobtainable value for 'last' if interval checking is disabled
          last = Oxidized.config.interval.zero? ? Time.now.utc + 10 : next_node.last.end
          break if last + Oxidized.config.interval > Time.now.utc
        end
        # shift nodes and get the next node
        node = @nodes.get
        node.running? ? next : node.running = true

        # 将节点依次加入队列消费
        @jobs.push Job.new node
        Oxidized.logger.debug "lib/oxidized/worker.rb: Added #{node.group}/#{node.name} to the job queue"
      end

      # 任务调度完成执行钩子函数
      run_done_hook if cycle_finished?
      Oxidized.logger.debug("lib/oxidized/worker.rb: #{@jobs.size} jobs running in parallel") unless @jobs.empty?
    end

    # 分析调度作业执行情况
    def process(job)
      node = job.node
      # 捕捉作业数据
      node.last    = job
      node.running = false
      node.stats.add job
      @jobs.duration job.time

      # 判断任务是否执行成功
      if job.status == :success
        process_success node, job
      else
        process_failure node, job
      end
    rescue NodeNotFound
      Oxidized.logger.warn "#{node.group}/#{node.name} not found, removed while collecting?"
    end

    private
      def process_success(node, job)
        # 更新执行成功的job
        @jobs_done += 1 # needed for :nodes_done hook
        Oxidized.hooks.handle(:node_success, node: node, job: job)

        msg = "update #{node.group}/#{node.name}"
        msg += " from #{node.from}" if node.from
        msg += " with message '#{node.msg}'" if node.msg

        # 配置转储
        output = node.output.new
        if output.store(node.name, job.config, msg: msg, email: node.email, user: node.user, group: node.group)
          node.modified
          Oxidized.logger.info "Configuration updated for #{node.group}/#{node.name}"
          Oxidized.hooks.handle(:post_store, node: node, job: job, commitref: output.commitref)
        end
        node.reset
      end

      # 更新执行失败的job
      def process_failure(node, job)
        msg = "#{node.group}/#{node.name} status #{job.status}"
        if node.retry < Oxidized.config.retries
          node.retry += 1

          msg += ", retry attempt #{node.retry}"
          @nodes.next node.name
        else
          # Only increment the @jobs_done when we give up retries for a node (or success).
          # As it would otherwise cause @jobs_done to be incremented with generic retries.
          # This would cause :nodes_done hook to desync from running at the end of the nodelist and
          # be fired when the @jobs_done > @nodes.count (could be mid-cycle on the next cycle).
          @jobs_done += 1

          msg += ", retries exhausted, giving up"

          node.retry = 0
          Oxidized.hooks.handle(:node_fail, node: node, job: job)
        end
        Oxidized.logger.warn msg
      end

      # 检查作业是否执行完毕
      def cycle_finished?
        if @jobs_done > @nodes.count
          true
        else
          @jobs_done.positive? && (@jobs_done % @nodes.count).zero?
        end
      end

      # 调用钩子函数并重置 @jobs_done
      def run_done_hook
        Oxidized.logger.debug "lib/oxidized/worker.rb: Running :nodes_done hook"
        Oxidized.hooks.handle :nodes_done
      rescue StandardError => e
        # swallow the hook erros and continue as normal
        Oxidized.logger.error "lib/oxidized/worker.rb: #{e.message}"
      ensure
        @jobs_done = 0
      end
  end
end
