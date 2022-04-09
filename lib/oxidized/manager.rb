# frozen_string_literal: true

module Oxidized
  require_relative "model/model"
  require_relative "input/input"
  require_relative "output/output"
  require_relative "source/source"

  # 动态
  class Manager
    # 类单例方法
    class << self
      def load(dir, file)
        # 动态加载模块
        require File.join(dir, "#{file}.rb")

        klass = nil
        [Oxidized, Object].each do |mod|
          klass = mod.constants.find { |const| const.to_s.casecmp(file).zero? }
          klass ||= mod.constants.find { |const| const.to_s.downcase == "oxidized" + file.downcase }
          klass = mod.const_get klass if klass
          break if klass
        end
        i = klass.new
        i&.setup if i&.respond_to? :setup
        { file => klass }
      rescue LoadError
        false
      end
    end

    # 基础属性方法
    attr_reader :input, :output, :source, :model, :hook

    def initialize
      @input  = {}
      @output = {}
      @source = {}
      @model  = {}
      @hook   = {}
    end

    def add_input(name)
      loader @input, Config::INPUT_DIR, "input", name
    end

    def add_output(name)
      loader @output, Config::OUTPUT_DIR, "output", name
    end

    def add_source(name)
      loader @source, Config::SOURCE_DIR, "source", name
    end

    def add_model(name)
      loader @model, Config::MODEL_DIR, "model", name
    end

    def add_hook(name)
      loader @hook, Config::HOOK_DIR, "hook", name
    end

    private
      def loader(hash, global_dir, local_dir, name)
        dir = File.join(Config::ROOT, local_dir)
        # 优先加载本地文件，其次为全局配置，如未加载则返回 false
        map = Manager.load(dir, name) if File.exist? File.join(dir, "#{name}.rb")
        map ||= Manager.load(global_dir, name) if File.exist? File.join(global_dir, "#{name}.rb")
        hash.merge!(map) if map
      end
  end
end
