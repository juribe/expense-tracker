# frozen_string_literal: true

module SourceRecognition
  # BankSetupWizard
  # Read model for the visual bank configuration wizard. It turns the same
  # bank groups rendered on the recognition page into ordered steps, exposing
  # the bank-level signals (senders/domains and subject/header patterns) and
  # the existing suggestions for the group's SEED source.
  #
  # It deliberately does not persist anything: accepting a suggestion and
  # saving goes through MoneySourcesController#update_recognition, which
  # reuses MoneySourceRecognition#replace_identifiers and the current
  # classification/validation rules.
  #
  # Example:
  #   SourceRecognition::BankSetupWizard.new(bank_groups).steps
  class BankSetupWizard
    BANK_SIGNAL_KINDS = %w[sender domain subject header].freeze

    Step = Struct.new(:key, :label, :source_id, :configured, :senders, :subjects, :suggestions,
                      keyword_init: true)

    def initialize(groups)
      @groups = groups
    end

    def steps
      @steps ||= @groups.reject { |group| group[:cash_only] }.map { |group| build_step(group) }
    end

    # A bank is configured only by its shared bank-level signals. Product
    # keywords belong to individual sources and never prove bank recognition.
    def self.bank_configured?(source)
      source.recognition_identifiers.any? do |identifier|
        identifier.confirmed? && BANK_SIGNAL_KINDS.include?(identifier.kind)
      end
    end

    # Confirmed values for the requested kinds, in the user's configured order.
    def self.confirmed_values(source, kinds)
      source.recognition_identifiers
            .select { |identifier| identifier.confirmed? && kinds.include?(identifier.kind) }
            .sort_by(&:position)
            .map(&:value)
    end

    private

    def build_step(group)
      seed = group[:seed]
      engine = SuggestionEngine.new(source: seed, group_members: group[:members] - [ seed ])
      suggestions = engine.call

      Step.new(
        key: group[:key],
        label: group[:label],
        source_id: seed.id,
        configured: self.class.bank_configured?(seed),
        senders: self.class.confirmed_values(seed, %w[sender domain]),
        subjects: self.class.confirmed_values(seed, %w[subject header]),
        suggestions: {
          senders: suggestions[:senders],
          subjects: suggestions[:subjects]
        }
      )
    end
  end
end
