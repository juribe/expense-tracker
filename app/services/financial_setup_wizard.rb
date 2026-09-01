# frozen_string_literal: true

# FinancialSetupWizard
# Describes the ordered onboarding steps and the finance kind each one manages.
# A single source of truth for the wizard flow so future source types (wallet,
# cash, debit card) plug in by adding a step without redesigning the app.
#
# Example: FinancialSetupWizard.steps.map(&:key) # => [:accounts, :credit_cards, :loans, :review]
class FinancialSetupWizard
  # FinancialStep
  # Value object describing one wizard step (kind, label key, icon, review label).
  Step = Struct.new(:key, :kind, :label_key, :icon, :review_noun_key, keyword_init: true)

  STEPS = [
    Step.new(key: :cash, kind: "cash", label_key: "wizard.steps.cash",
             icon: "cash", review_noun_key: "wizard.review.cash"),
    Step.new(key: :accounts, kind: "account", label_key: "wizard.steps.accounts",
             icon: "bank", review_noun_key: "wizard.review.accounts"),
    Step.new(key: :credit_cards, kind: "credit_card", label_key: "wizard.steps.credit_cards",
             icon: "credit-card-2-front", review_noun_key: "wizard.review.credit_cards"),
    Step.new(key: :loans, kind: "loan", label_key: "wizard.steps.loans",
             icon: "cash-coin", review_noun_key: "wizard.review.loans"),
    Step.new(key: :review, kind: nil, label_key: "wizard.steps.review",
             icon: "check2-circle", review_noun_key: nil)
  ].freeze

  CHOICES = %w[manual import skip].freeze

  class << self
    def steps
      STEPS
    end

    def step_keys
      STEPS.map(&:key)
    end

    def step(key)
      STEPS.find { |step| step.key == key.to_sym }
    end

    # Steps that manage a financial source kind (all but review).
    def source_steps
      STEPS.reject { |step| step.kind.nil? }
    end

    def source_step_keys
      source_steps.map(&:key)
    end

    def choice?(value)
      CHOICES.include?(value.to_s)
    end

    def valid_choice!(value)
      raise ArgumentError, "invalid wizard choice: #{value.inspect}" unless choice?(value)
    end

    # Stable lookup key for duplicate detection, shared by the controller, the
    # import-review view and the completer. Accepts ParsedStatement (symbol
    # keys) or the stored JSON hash (string keys).
    def duplicate_key(source)
      data = source.is_a?(Hash) ? source : source.to_h
      identifier = data[:identifier].presence || data["identifier"].presence
      return identifier.to_s.strip if identifier

      bank = data[:bank].presence || data["bank"].presence
      last_four = data[:card_last_four].presence || data["card_last_four"].presence
      [ bank, last_four ].compact.join("-")
    end
  end
end
