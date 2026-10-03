# frozen_string_literal: true

module Statements
  # ReviewBuilder
  # Turns a parsed Statements::Document into the review the apply-payment
  # flow renders: expense candidates (enriched with classification reuse and
  # duplicate flags against the user's existing expenses), the income
  # movements kept out of the candidates, and a payment suggestion built from
  # the statement summary or the statement's own payment movement.
  #
  #   review = Statements::ReviewBuilder.call(user: user, document: document,
  #                                           money_source: card)
  #   review.candidates # => [ExpenseCandidate, ...]
  class ReviewBuilder
    Review = Struct.new(:summary, :source, :candidates, :credits,
                        :payment_suggestion, keyword_init: true)

    def self.call(user:, document:, money_source: nil)
      new(user: user, document: document, money_source: money_source).build
    end

    def initialize(user:, document:, money_source: nil)
      @user = user
      @document = document
      @money_source = money_source
    end

    def build
      Review.new(
        summary: @document.summary,
        source: @document.source,
        candidates: expense_candidates,
        credits: dated_credits,
        payment_suggestion: payment_suggestion
      )
    end

    private

    include Expenses::ValueParsing

    def expense_candidates
      candidates = Expenses::FileImport::CandidateBuilder.new(context: context)
                                                            .from_transactions(@document.expense_movements)
      candidates.each { |candidate| link_candidate(candidate) }
      Expenses::FileImport::Enrichers::Activity.new(user: @user).call(candidates, @document.engine)
      Expenses::FileImport::Enrichers::Confidence.new.call(candidates)
      ExpensePlayground::DuplicateDetector.new(user: @user).flag(candidates)
      candidates
    end

    # With an explicit target every movement belongs to it; otherwise the
    # statement's own source decides (verified by card last four, else a
    # unique bank + kind match among the user's active sources).
    def link_candidate(candidate)
      candidate.source = "statement_file"
      if target_source
        candidate.money_source_id = target_source.id
        candidate.money_source_name = target_source.name
        candidate.money_source_source = "statement"
      else
        candidate.money_source_source = "missing"
      end
    end

    def target_source
      return @money_source if @money_source
      return @statement_source if defined?(@statement_source)

      statement = @document.source
      @statement_source =
        if statement
          MoneySources::Match.call(user: @user, card_last_four: last_four(statement)) ||
            unique_bank_and_kind_match(statement)
        end
    end

    def last_four(statement)
      digits = (statement.identifier.presence || statement.card_last_four.presence).to_s.gsub(/\D/, "")
      digits[-4..] if digits.length >= 4
    end

    def unique_bank_and_kind_match(statement)
      bank = statement.bank.to_s.strip
      kind = statement.kind.to_s
      return if bank.blank? || kind.blank?

      matches = @user.money_sources.active.select do |source|
        source.kind == kind && normalize_name(source.bank) == normalize_name(bank)
      end
      matches.one? ? matches.first : nil
    end

    # Income rows are display-only data; their date fields normalize to Date
    # objects so the review can print them with the standard locale helpers.
    def dated_credits
      @document.income_movements.map { |movement| movement.merge(date: parse_date(movement[:date])) }
    end

    def context
      @context ||= Expenses::FileImport::ImportContext.new(@user)
    end

    def payment_suggestion
      suggestion = @document.income_movements.first ? movement_suggestion : summary_suggestion
      return if suggestion.nil?

      suggestion[:principal_amount] = [ suggestion[:amount] - interest_charged, BigDecimal("0") ].max
      suggestion[:interest_amount] = interest_charged
      suggestion[:insurance_amount] = BigDecimal("0")
      suggestion[:other_amount] = BigDecimal("0")
      suggestion
    end

    def movement_suggestion
      movement = @document.income_movements.first
      amount = parse_amount(movement[:amount])
      return if amount.nil?

      { date: parse_date(movement[:date]), amount: amount, description: payment_description }
    end

    def summary_suggestion
      summary = @document.summary
      return if summary.blank? || summary.total_due.blank?

      { date: summary.due_date, amount: summary.total_due, description: payment_description }
    end

    def interest_charged
      summary = @document.summary
      return BigDecimal("0") if summary.blank? || summary.interest_charged.blank?

      summary.interest_charged
    end

    def payment_description
      I18n.t("statement_imports.payment_description",
             target: @money_source&.name || @document.source&.display_name)
    end
  end
end
