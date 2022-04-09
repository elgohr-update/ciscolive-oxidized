# frozen_string_literal: true

require "fileutils"

module Oxidized
  class OxidizedError < StandardError; end

  DIRECTORY = File.expand_path(File.join(File.dirname(__FILE__), "../"))

  require "oxidized/version"
  require "oxidized/string"
  require "oxidized/config"
  require "oxidized/config/vars"
  require "oxidized/worker"
  require "oxidized/nodes"
  require "oxidized/manager"
  require "oxidized/hook"
  require "oxidized/core"

  # 模块全局变量
  def self.asetus
    @@asetus
  end

  def self.asetus=(val)
    @@asetus = val
  end

  def self.config
    asetus.cfg
  end

  def self.logger
    @@logger
  end

  def self.logger=(val)
    @@logger = val
  end

  def self.setup_logger
    # 检查是否存在文件夹，不存在则新建
    FileUtils.mkdir_p(Config::LOG) unless File.directory?(Config::LOG)

    if config.has_key?("use_syslog") && config.use_syslog
      require "syslog/logger"
      @@logger = Syslog::Logger.new("oxidized")
    else
      require "logger"
      if config.has_key?("log")
        @@logger = Logger.new(File.expand_path(config.log))
      else
        @@logger = Logger.new(STDERR)
      end
    end
    # 设置缺省日志级别
    logger.level = Logger::INFO unless config.debug
  end
end
