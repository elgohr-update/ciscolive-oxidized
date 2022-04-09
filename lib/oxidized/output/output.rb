# frozen_string_literal: true

module Oxidized
  class Output
    class NoConfig < OxidizedError; end

    def cfg_to_str(cfg)
      # cfg.select { |h| h[:type] == "cfg" }.map { |h| h[:data] }.join
      cfg.filter_map { |h| h[:data] if h[:type] == "cfg" }.join
    end
  end
end
