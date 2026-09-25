# frozen_string_literal: true

module ExpenseResolver
  class MoneySourceResult
    Result = Struct.new(:money_source, :money_source_name, :review) do
    end

    attr_accessor :expense, :user, :money_source_detector, :rules, :text

    def self.call(expense:, user:, money_source_detector: nil, rules: nil, text: nil)
      new(expense: expense, user: user, money_source_detector: money_source_detector, rules: rules, text: text).call
    end

    def initialize(expense:, user:, money_source_detector: nil, rules: nil, text: nil)
      self.expense = expense
      self.user = user
      self.money_source_detector = money_source_detector
      self.rules = rules
      self.text = text
    end

    def call
      # Channel processors may have already detected the source (e.g. the
      # image pipeline from the user's note or the receipt's OCR text); in
      # that case the pre-set id wins and no detection runs.
      return preset_result if preset_money_source?

      source, review = resolve_money_source
      # Nothing is invented or suggested when no registered source matches:
      # the expense keeps its source empty for the user to pick.
      return Result.new(nil, nil) if source.nil?

      Result.new(source, source.name, review)
    end

    private

    def preset_money_source?
      expense.respond_to?(:money_source_id) && expense.money_source_id.present?
    end

    def preset_result
      source = user&.money_sources&.find_by(id: expense.money_source_id)
      Result.new(source, source&.name || expense.money_source_name)
    end

    # Layered recognition scoped to the entry:
    #   1. The AI hint, restricted to the registered vocabulary at split time:
    #      a registered hint resolves directly; an unregistered one means the
    #      expense named its own (unknown) source, so nothing is inherited.
    #   2. The entry's own slice (from its amount onward) scored by matched
    #      values (name, bank, confirmed keywords): the strongest source wins;
    #      a tied score still selects the first but is flagged for review.
    #   3. A slice that explicitly names a payment method no registered source
    #      matches never inherits another expense's source.
    #   4. The full text supplies the source only when exactly one registered
    #      source matches anywhere ("...todo con Davibank"); with several
    #      distinct sources in the message a silent entry stays empty.
    def resolve_money_source
      detector = money_source_detector
      hint = expense.respond_to?(:money_source_hint) ? expense.money_source_hint.to_s : ""

      if hint.present?
        matched = detector.best_match(hint)
        return [ matched&.first, false ]
      end

      slice = own_amount_slice(expense.original_text.to_s)

      slice_matches = detector.scored_matches(slice)
      return resolve_scored(slice_matches) if slice_matches.any?

      return [ nil, false ] if MoneySources::Detector.payment_mention?(slice)

      resolve_from_full_text(detector)
    end

    # The best score wins; when several sources tie at the top the first one
    # is still selected, but marked for review.
    def resolve_scored(matches)
      best = matches.max_by { |_, matched| matched.size }
      tie = matches.count { |_, matched| matched.size == best.last.size } > 1

      [ best.first, tie ]
    end

    # The meaningful slice starts at the expense's own amount; anything before
    # it (previous expense's description tail and payment mention) is another
    # expense's business.
    def own_amount_slice(fragment)
      first_amount = ExpenseResolver::Amounts::Service.scan_amounts(fragment).first
      first_amount ? fragment[first_amount[:start]..] : fragment
    end

    def resolve_from_full_text(detector)
      full = text.presence
      return [ nil, false ] if full.blank?

      matches = detector.matching_sources(full)
      matches.one? ? [ matches.first, false ] : [ nil, false ]
    end
  end
end
