# frozen_string_literal: true

module Expenses
  # CandidateDeduplicator
  # One message can describe the same transaction twice — a caption naming the
  # expense plus an attached confirmation screenshot repeating the amount —
  # and the parser may emit both as separate entries. When two entries of the
  # same message share date, amount magnitude and money source, only the most
  # complete one survives (ties keep the first in text order) and the kept
  # entry records that a duplicate was skipped.
  #
  # Entries without a resolved money source are never merged: equal small
  # purchases on the same day are too common to risk dropping real data.
  #
  # Example: Expenses::CandidateDeduplicator.call(candidates)
  class CandidateDeduplicator
    DUPLICATE_SKIPPED_WARNING = "Another entry in the same message shared its date, amount and " \
                                "money source; it was skipped as a duplicate."

    def self.call(candidates)
      new(candidates).call
    end

    def initialize(candidates)
      @candidates = candidates.to_a
    end

    def call
      groups = {}
      order = []

      @candidates.each do |candidate|
        key = signature(candidate)
        if key.nil?
          groups[candidate.object_id] = [ candidate ]
          order << candidate.object_id
        elsif groups.key?(key)
          groups[key] << candidate
        else
          groups[key] = [ candidate ]
          order << key
        end
      end

      order.flat_map do |key|
        group = groups[key]
        next group if group.size == 1

        kept = most_complete(group)
        mark_skipped_duplicate(kept)
        [ kept ]
      end
    end

    private

    def signature(candidate)
      return nil if candidate.date.blank? || candidate.amount.blank?
      return nil if candidate.money_source_id.blank?

      amount = candidate.amount.to_d.abs
      return nil unless amount.positive?

      [ candidate.date.to_date, format("%.2f", amount), candidate.money_source_id ]
    end

    def most_complete(group)
      group.min_by { |candidate| [ candidate.category_id, candidate.description ].count(&:blank?) }
    end

    def mark_skipped_duplicate(candidate)
      return unless candidate.warnings.is_a?(Array)

      candidate.warnings << DUPLICATE_SKIPPED_WARNING
    end
  end
end
