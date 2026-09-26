# frozen_string_literal: true

module ExpenseResolver
  class MoneySourceResult
    Result = Struct.new(:money_source, :money_source_name, :review) do
    end

    attr_accessor :expense, :user, :money_source_detector, :rules, :text

    def self.call(expense:, user:, money_source_detector: nil, rules: nil, text: nil)
      new(expense: expense, user: user, money_source_detector: money_source_detector, rules: rules, text: text).call
    end

    # The expense's own side of its fragment: from its first amount onward,
    # with trailing payment clauses removed (they belong to the message).
    def self.slice_for(expense)
      fragment = expense.original_text.to_s
      first_amount = ExpenseResolver::Amounts::Service.scan_amounts(fragment).first
      slice = first_amount ? fragment[first_amount[:start]..] : fragment
      ExpenseResolver::Text::Service.cut_payment_clause(slice)
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
    #      distinct sources in the message a silent entry stays empty —
    #      unless a trailing quantified clause ("...todo con X") names the
    #      source explicitly, which applies to every expense in the message.
    def resolve_money_source
      detector = money_source_detector
      hint = expense.respond_to?(:money_source_hint) ? expense.money_source_hint.to_s : ""

      slice = self.class.slice_for(expense)

      if hint.present?
        source = detector.best_match(hint)&.first
        # An unregistered hint names an unknown source: nothing is inherited.
        return [ nil, false ] if source.nil?

        # The hint is authoritative only when the fragment actually names the
        # source; a hint over a bank-level-only fragment is the model's guess,
        # so it is selected but flagged for review. In a transfer, the
        # destination clause ("a mi cuenta de ahorros") describes where the
        # money lands, not how it was paid: grounding is judged on the origin
        # side only, so destination words can never silently ground a source.
        grounded = detector.grounded_in?(source, origin_slice(slice))
        return [ source, !grounded ]
      end

      slice_matches = detector.scored_matches(slice)
      return resolve_scored(slice_matches) if slice_matches.any?

      return [ nil, false ] if MoneySources::Detector.payment_mention?(slice)

      resolve_from_full_text(detector)
    end

    # In a transfer ("pasé X de Davibank a mi cuenta de ahorros"), words after
    # the destination marker belong to the destination account. Tokens there
    # must not ground a money source: only the origin side may.
    DESTINATION_CLAUSE_REGEX = /\b(?:a|hacia)\s+(?:mi|mis|la|el|una|unas|otra|otro|otras|otros)\s+cuenta\b/i

    def origin_slice(slice)
      match = slice.match(DESTINATION_CLAUSE_REGEX)
      match ? slice[0...match.begin(0)] : slice
    end

    # The best score wins; when several sources tie at the top the first one
    # is still selected, but marked for review.
    def resolve_scored(matches)
      best = matches.max_by { |_, score| score }
      tie = matches.count { |_, score| score == best.last } > 1

      [ best.first, tie ]
    end

    # The meaningful slice starts at the expense's own amount; anything before
    # it (previous expense's description tail and payment mention) is another
    # expense's business.
    def resolve_from_full_text(detector)
      full = text.presence
      return [ nil, false ] if full.blank?

      # Explicit per-name assignments ("El restaurante lo pagué con la cuenta
      # Davibank") are the most specific signal: they attribute a source to
      # the expense whose description names it.
      named = named_assignment_clause(full)
      if named && description_matches_name?(named[:name])
        named_matches = detector.scored_matches(named[:clause])
        return resolve_scored(named_matches) if named_matches.any?
      end

      # A trailing quantified clause ("...todo con Davibank", "...ambas con
      # Nequi") says one payment method applies to every expense, so it
      # resolves even when several sources match elsewhere in the message.
      clause = trailing_payment_clause(full)
      if clause
        clause_matches = detector.scored_matches(clause)
        return resolve_scored(clause_matches) if clause_matches.any?
      end

      # A remainder clause ("...y lo demás en efectivo") covers the expenses
      # that were not named explicitly.
      remainder = remainder_clause(full)
      if remainder
        remainder_matches = detector.scored_matches(remainder)
        return resolve_scored(remainder_matches) if remainder_matches.any?
      end

      matches = detector.matching_sources(full)
      matches.one? ? [ matches.first, false ] : [ nil, false ]
    end

    # The quantified payment clause at the end of the message, or nil. The
    # same pattern Text::Service cuts from descriptions — there it keeps the
    # phrase out of descriptions, here it scopes it for source attribution.
    def trailing_payment_clause(full)
      clean = ExpenseResolver::Text::Service.normalize_text(full)
      match = clean.match(ExpenseResolver::Text::Service::PAYMENT_CLAUSE_REGEX)
      match ? clean[match.begin(0)..] : nil
    end

    # "El restaurante lo pagué con la cuenta Davibank": the name references
    # an expense by its description word.
    def named_assignment_clause(full)
      clean = ExpenseResolver::Text::Service.normalize_text(full)
      match = clean.match(/[,;.]?\s*(?:el|la|los|las)?\s*(?<name>\w[\wáéíóúñ]*)\s+lo\s+pag\p{L}*\s+con\s+(?<clause>[^,;.]+)/i)
      return nil unless match

      { name: match[:name], clause: match[:clause] }
    end

    # "…y lo demás en efectivo": the payment method for every expense that
    # was not explicitly named.
    def remainder_clause(full)
      clean = ExpenseResolver::Text::Service.normalize_text(full)
      match = clean.match(/\b(?:lo demas|los demas|el resto|todo lo demas)\s+(?:pago\s+)?(?:con|en|desde|mediante|usando)\s+(?<clause>[^,;.]+)/i)
      match ? match[:clause] : nil
    end

    def description_tokens
      @description_tokens ||= ExpenseResolver::Text::Service
        .normalize_text(expense.description.to_s).split
    end

    # The named expense matches when one of its description tokens (4+ chars,
    # to skip noise) is the referenced name.
    def description_matches_name?(name)
      name_tokens = ExpenseResolver::Text::Service.normalize_text(name).split
      description_tokens.any? { |token| token.length >= 4 && name.include?(token) }
    end
  end
end
