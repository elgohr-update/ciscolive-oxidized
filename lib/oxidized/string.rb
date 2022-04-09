# frozen_string_literal: true

module Oxidized
  # Used in models, contains convenience methods
  class String < String
    # 重写 String 类，增加 type cmd name 属性
    attr_accessor :type, :cmd, :name

    # 初始化入口
    def initialize(str = "")
      super
      return unless str.class == Oxidized::String
      # 设置类对象属性
      @cmd  = str.cmd
      @name = str.name
      @type = str.type
    end

    # @return [Oxidized::String] copy of self with last line removed
    # 移除倒数【第 N(一) 行】字串
    def cut_tail(lines = 1)
      Oxidized::String.new each_line.to_a[0..-1 - lines].join
    end

    # @return [Oxidized::String] copy of self with first line removed
    # 移除正数【第 N(一) 行】字串
    def cut_head(lines = 1)
      Oxidized::String.new each_line.to_a[lines..-1].join
    end

    # @return [Oxidized::String] copy of self with first and last lines removed
    # 移除首尾【X,Y行】字串
    def cut_both(head = 1, tail = 1)
      Oxidized::String.new each_line.to_a[head..-1 - tail].join
    end

    # sets @cmd and @name unless @name is already set
    # 设置字串命令行和 name 属性
    def set_cmd(command)
      @cmd = command

      @name ||= @cmd.to_s.strip.gsub(/\s+/, "_") # what to do when command is proc? #to_s seems ghetto
    end
  end
end
