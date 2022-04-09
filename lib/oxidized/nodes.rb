# frozen_string_literal: true

module Oxidized
  require "ipaddr"
  require_relative "node"

  class Oxidized::NotSupported < OxidizedError; end

  class Oxidized::NodeNotFound < OxidizedError; end

  class Nodes < Array
    # 类对象属性
    attr_accessor :source, :jobs

    # 方法别名
    alias put unshift

    # 加载对象
    def load(node_want = nil)
      with_lock do
        new = []
        # 加载设备清单
        @source = Oxidized.config.source.default
        Oxidized.mgr.add_source(@source) || raise(MethodNotFound, "cannot load node source '#{@source}', not found")
        Oxidized.logger.info "lib/oxidized/nodes.rb: Loading nodes"

        # 实例化对象
        nodes = Oxidized.mgr.source[@source].new.load node_want
        nodes.each do |node|
          # we want to load specific node(s), not all of them
          # 加载部分清单，而非全量清单。默认加载全量清单
          next unless node_want? node_want, node

          begin
            node_obj = Node.new node
            new.push node_obj
          rescue ModelNotFound => err
            Oxidized.logger.error "node %s raised %s with message '%s'" % [node, err.class, err.message]
          rescue Resolv::ResolvError => err
            Oxidized.logger.error "node %s is not resolvable, raised %s with message '%s'" % [node, err.class, err.message]
          end
        end
        size.zero? ? replace(new) : update_nodes(new)
        Oxidized.logger.info "lib/oxidized/nodes.rb: Loaded #{size} nodes"
      end
    end

    # 根据入参判断是否与节点的IP、主机名相同
    def node_want?(node_want, node)
      return true unless node_want

      node_want_ip = (IPAddr.new(node_want) rescue false)
      name_is_ip   = (IPAddr.new(node[:name]) rescue false)
      if name_is_ip && (node_want_ip == node[:name])
        true
      elsif node[:ip] && (node_want_ip == node[:ip])
        true
      elsif node_want.match node[:name]
        true unless name_is_ip
      end
    end

    # 全量节点数据
    def list
      with_lock do
        map { |e| e.serialize }
      end
    end

    # 获取特定节点数据
    def show(node)
      with_lock do
        i = find_node_index node
        self[i].serialize
      end
    end

    # 根据节点名称、属性查询查询配置对象
    def fetch(node_name, group)
      yield_node_output(node_name) do |node, output|
        output.fetch node, group
      end
    end

    # @param node [String] name of the node moved into the head of array
    # 获取下一个节点信息
    def next(node, opt = {})
      return unless waiting.find_node_index(node)

      with_lock do
        n       = del node
        n.user  = opt["user"]
        n.email = opt["email"]
        n.msg   = opt["msg"]
        n.from  = opt["from"]
        # set last job to nil so that the node is picked for immediate update
        n.last = nil
        # 此处为方法别名，向列表头部添加元素
        put n
        jobs.want += 1 if Oxidized.config.next_adds_job?
      end
    end
    alias top next

    # @return [String] node from the head of the array
    # FIFO 先进先出队列逻辑
    def get
      with_lock do
        (self << shift).last
      end
    end

    # @param node node whose index number in Nodes to find
    # @return [Fixnum] index number of node in Nodes
    def find_node_index(node)
      find_index(node) || raise(Oxidized::NodeNotFound, "unable to find '#{node}'")
    end

    # 根据节点名称、属组查询其相关的配置版本信息
    def version(node_name, group)
      yield_node_output(node_name) do |node, output|
        output.version node, group
      end
    end

    # 根据节点名称、属组和OID查询特定版本信息
    def get_version(node_name, group, oid)
      yield_node_output(node_name) do |node, output|
        output.get_version node, group, oid
      end
    end

    # 根据节点名称、属性以及OID 获取配置差量
    def get_diff(node_name, group, oid1, oid2)
      yield_node_output(node_name) do |node, output|
        output.get_diff node, group, oid1, oid2
      end
    end

    private
      def initialize(opts = {})
        super()
        node   = opts.delete :node
        @mutex = Mutex.new # we compete for the nodes with webapi thread
        if (nodes = opts.delete(:nodes))
          replace nodes
        else
          load node
        end
      end

      # 同步锁机制
      def with_lock(&block)
        @mutex.synchronize(&block)
      end

      # 查询节点索引
      def find_index(node)
        index { |e| [e.name, e.ip].include? node }
      end

      # @param node node which is removed from nodes list
      # @return [Node] deleted node
      def del(node)
        delete_at find_node_index(node)
      end

      # @return [Nodes] list of nodes running now
      def running
        Nodes.new nodes: select { |node| node.running? }
      end

      # @return [Nodes] list of nodes waiting (not running)
      def waiting
        Nodes.new nodes: select { |node| not node.running? }
      end

      # walks list of new nodes, if old node contains same name, adds last and
      # stats information from old to new.
      #
      # @todo can we trust name to be unique identifier, what about when groups are used?
      # @param [Array] nodes Array of nodes used to replace+update old
      def update_nodes(nodes)
        old = dup
        replace(nodes)
        each do |node|
          if (i = old.find_node_index(node.name))
            node.stats = old[i].stats
            node.last  = old[i].last
          end
        rescue Oxidized::NodeNotFound
        end
        sort_by! { |x| x.last.nil? ? Time.new(0) : x.last.end }
      end

      # 过滤节点执行代码块
      def yield_node_output(node_name)
        with_lock do
          node   = find { |n| n.name == node_name }
          output = node.output.new
          raise Oxidized::NotSupported unless output.respond_to? :fetch

          yield node, output
        end
      end
  end
end
