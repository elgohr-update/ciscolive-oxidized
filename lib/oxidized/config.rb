# frozen_string_literal: true

module Oxidized
  require "asetus"

  class NoConfig < OxidizedError; end

  class InvalidConfig < OxidizedError; end

  # 模块单例方法属性
  class << self
    attr_accessor :mgr, :hooks
  end

  # 模块配置类对象
  class Config
    ROOT  = ENV["OXIDIZED_HOME"] || File.join(ENV["HOME"], ".config", "oxidized")
    CRASH = File.join(ENV["OXIDIZED_LOGS"] || ROOT, "crash")
    LOG   = File.join(ENV["OXIDIZED_LOGS"] || ROOT, "logs")
    SLEEP = 1

    # 项目文件夹
    INPUT_DIR  = File.join DIRECTORY, %w[lib oxidized input]
    OUTPUT_DIR = File.join DIRECTORY, %w[lib oxidized output]
    MODEL_DIR  = File.join DIRECTORY, %w[lib oxidized model]
    SOURCE_DIR = File.join DIRECTORY, %w[lib oxidized source]
    HOOK_DIR   = File.join DIRECTORY, %w[lib oxidized hook]

    # 类方法，加载初始化配置
    def self.load(cmd_opts = {})
      asetus          = Asetus.new(name: "oxidized", load: false, key_to_s: true, usrdir: Oxidized::Config::ROOT)
      Oxidized.asetus = asetus

      # 配置对象初始化、缺省配置
      asetus.default.username    = "cisco"
      asetus.default.password    = "cisco"
      asetus.default.model       = "ios"
      asetus.default.resolve_dns = true # if false, don't resolve DNS to IP
      asetus.default.interval    = 3600
      asetus.default.use_syslog  = false
      asetus.default.debug       = false
      asetus.default.threads     = 30
      asetus.default.timeout     = 15
      asetus.default.retries     = 1
      asetus.default.prompt      = /^([\w.@-]+[#>]\s?)$/
      asetus.default.rest        = "127.0.0.1:8888" # or false to disable
      asetus.default.vars        = {} # could be 'enable'=>'enablePW'
      asetus.default.groups      = {} # group level configuration
      asetus.default.models      = {} # model level configuration
      asetus.default.pid         = File.join(Oxidized::Config::ROOT, "pid")
      # if true, /next adds job, so device is fetched immmeiately
      asetus.default.next_adds_job = true

      asetus.default.crash.directory = File.join(Oxidized::Config::ROOT, "crashes")
      asetus.default.crash.hostnames = false

      # 版本控制保留历史文件夹数量
      asetus.default.stats.history_size = 10
      asetus.default.input.default      = "ssh, telnet"
      asetus.default.input.debug        = true # or String for session log file
      asetus.default.input.ssh.secure   = false # complain about changed certs
      asetus.default.input.ftp.passive  = true # ftp passive mode
      asetus.default.input.utf8_encoded = true # configuration is utf8 encoded or ascii-8bit

      asetus.default.output.default = "file" # file, git
      asetus.default.source.default = "csv" # csv, sql

      asetus.default.model_map = {
        juniper: "junos",
        cisco:   "ios"
      }

      begin
        asetus.load # load system+user configs, merge to Config.cfg
      rescue StandardError => error
        raise InvalidConfig, "Error loading config: #{error.message}"
      end

      raise NoConfig, "edit ~/.config/oxidized/config" if asetus.create

      # override if comand line flag given
      asetus.cfg.debug = cmd_opts[:debug] if cmd_opts[:debug]

      asetus
    end
  end
end
