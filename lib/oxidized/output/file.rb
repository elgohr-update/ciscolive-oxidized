# frozen_string_literal: true

module Oxidized
  class OxidizedFile < Output
    require "fileutils"

    attr_reader :commitref

    def initialize
      @cfg = Oxidized.config.output.file
    end

    # 初始化对象，如果用户已定义则自动跳出
    def setup
      return unless @cfg.empty?

      Oxidized.asetus.user.output.file.directory = File.join(Config::ROOT, "configs")
      Oxidized.asetus.save :user
      raise NoConfig, "no output file config, edit ~/.config/oxidized/config"
    end

    # 配置转储
    def store(node, outputs, opt = {})
      file = File.expand_path @cfg.directory
      file = File.join File.dirname(file), opt[:group] if opt[:group]
      FileUtils.mkdir_p file
      file = File.join file, node
      File.open(file, "w") { |fh| fh.write outputs.to_cfg }
      @commitref = file
    end

    # 查询配置
    def fetch(node, group)
      cfg_dir   = File.expand_path @cfg.directory
      node_name = node.name

      # 配置优先存储到用户定义属组，如未定义使用缺省的基础文件夹
      # 否则遍历所有文件夹确定最终文件路径
      if group
        cfg_dir = File.join File.dirname(cfg_dir), group
        File.read File.join(cfg_dir, node_name)
      elsif File.exist? File.join(cfg_dir, node_name) # node configuration file is stored on base directory
        File.read File.join(cfg_dir, node_name)
      else
        path = Dir.glob(File.join(File.dirname(cfg_dir), "**", node_name)).first # fetch node in all groups
        File.read path
      end
    rescue Errno::ENOENT
      nil
    end

    def version(_node, _group)
      # not supported
      []
    end

    def get_version(_node, _group, _oid)
      "not supported"
    end
  end
end
