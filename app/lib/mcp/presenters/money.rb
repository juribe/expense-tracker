# frozen_string_literal: true

module Mcp
  module Presenters
    # Money
    # Serializes monetary values as exact decimal strings so no precision is
    # lost between BigDecimal and the agent.
    module Money
      module_function

      def money(value)
        return nil if value.nil?

        value.to_d.to_s("F")
      end
    end
  end
end
