# frozen_string_literal: true

module Mcp
  module Presenters
    # PocketPresenter
    # Real pocket balance plus the part reserved by savings goals.
    class PocketPresenter
      include Mcp::Presenters::Money

      def initialize(source)
        @source = source
      end

      def as_json
        {
          id: source.id,
          name: source.name,
          balance: money(source.balance),
          allocated_amount: money(allocated_amount),
          unallocated_amount: money([ source.balance - allocated_amount, 0 ].max),
          active: source.active
        }
      end

      private

      attr_reader :source

      # Sums in memory when the association was eager loaded, so listing
      # pockets never triggers one query per pocket.
      def allocated_amount
        if source.goal_allocations.loaded?
          source.goal_allocations.sum(&:amount).to_d
        else
          source.allocated_amount
        end
      end
    end
  end
end
