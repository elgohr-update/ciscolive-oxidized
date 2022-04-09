# frozen_string_literal: true

module Oxidized
  class Source
    class NoConfig < OxidizedError; end

    # 类对象实例化入口
    def initialize
      @map = Oxidized.config.model_map || {}
    end

    # 是否存在转义
    def map_model(model)
      @map.has_key?(model) ? @map[model] : model
    end

    # 节点变量插值
    def node_var_interpolate(var)
      case var
      when "nil" then nil
      when "false" then false
      when "true" then true
      else var
      end
    end
  end
end
