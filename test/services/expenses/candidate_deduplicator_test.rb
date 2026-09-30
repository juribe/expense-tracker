# frozen_string_literal: true

require "test_helper"

module Expenses
  class CandidateDeduplicatorTest < ActiveSupport::TestCase
    test "keeps the most complete entry when two share date, amount and money source" do
      complete = candidate(description: "Comida", category_id: 41)
      incomplete = candidate(description: "Cuenta De Ahorros 7273 a Nequi", category_id: nil)

      result = CandidateDeduplicator.call([ complete, incomplete ])

      assert_equal [ complete ], result
      assert_includes complete.warnings, CandidateDeduplicator::DUPLICATE_SKIPPED_WARNING
    end

    test "keeps the earlier entry when both are equally complete" do
      first = candidate(description: "Comida")
      second = candidate(description: "Comida otra vez")

      result = CandidateDeduplicator.call([ first, second ])

      assert_equal [ first ], result
    end

    test "keeps the later entry when it is the more complete one" do
      incomplete = candidate(description: "pago", category_id: nil)
      complete = candidate(description: "Comida", category_id: 41)

      result = CandidateDeduplicator.call([ incomplete, complete ])

      assert_equal [ complete ], result
      assert_includes complete.warnings, CandidateDeduplicator::DUPLICATE_SKIPPED_WARNING
    end

    test "keeps entries that only differ in description but share signature" do
      first = candidate(description: "Comida")
      second = candidate(description: "Cine")

      assert_equal [ first ], CandidateDeduplicator.call([ first, second ])
    end

    test "never merges entries without a resolved money source" do
      first = candidate(description: "Comida", money_source_id: nil)
      second = candidate(description: "Cine", money_source_id: nil)

      result = CandidateDeduplicator.call([ first, second ])

      assert_equal [ first, second ], result
    end

    test "keeps entries with different dates, amounts or sources" do
      yesterday = candidate(description: "Comida", date: Date.current - 1)
      other_amount = candidate(description: "Comida", amount: 2000)
      other_source = candidate(description: "Comida", money_source_id: 8)

      result = CandidateDeduplicator.call([ yesterday, other_amount, other_source ])

      assert_equal [ yesterday, other_amount, other_source ], result
    end

    test "compares amount magnitude, not sign" do
      negative = candidate(description: "Comida", amount: -1000)
      positive = candidate(description: "Comida", amount: 1000)

      assert_equal [ negative ], CandidateDeduplicator.call([ negative, positive ])
    end

    test "keeps entries missing date or amount" do
      no_date = candidate(description: "Comida", date: nil)
      no_amount = candidate(description: "Comida", amount: nil)
      normal = candidate(description: "Comida")

      result = CandidateDeduplicator.call([ no_date, no_amount, normal ])

      assert_equal [ no_date, no_amount, normal ], result
    end

    test "preserves text order of the kept entries" do
      first = candidate(description: "Comida", category_id: 41)
      noise = candidate(description: "Transporte", amount: 5000)
      duplicate_of_first = candidate(description: "Cuenta De Ahorros 7273 a Nequi", category_id: nil)

      result = CandidateDeduplicator.call([ first, noise, duplicate_of_first ])

      assert_equal [ first, noise ], result
    end

    private

    def candidate(description:, date: Date.current, amount: 1000, money_source_id: 21, category_id: nil)
      ExpenseCandidate.new(
        amount: amount,
        date: date,
        description: description,
        category_id: category_id,
        money_source_id: money_source_id,
        warnings: []
      )
    end
  end
end
