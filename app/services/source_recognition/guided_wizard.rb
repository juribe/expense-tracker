# frozen_string_literal: true

module SourceRecognition
  # GuidedWizard
  # Read model for the guided money-source recognition modal. It walks the
  # user's payment sources in a stable order and prepares the illustrative
  # data each step renders (email preview, natural-language examples and the
  # existing pending suggestions).
  #
  # It deliberately owns no persistence: saving goes through
  # MoneySourcesController#update_recognition, the same endpoint used by the
  # manual recognition page.
  #
  # Example:
  #   steps = SourceRecognition::GuidedWizard.for_user(user)
  #   steps.first.current       # => MoneySource
  #   steps.first.email_preview # => { sender_name:, sender_address:, subject:, body:, highlights: }
  class GuidedWizard
    class << self
      # One step per payment source, sharing a single preloaded collection.
      def for_user(user)
        sources = sources_for(user).to_a
        sources.map { |source| new(user: user, source_id: source.id, sources: sources) }
      end

      def sources_for(user)
        user.money_sources
            .payment_sources
            .includes(:recognition_identifiers, recognition: :recognition_identifiers)
            .order(:kind, :name)
      end
    end

    attr_reader :sources, :current, :index

    def initialize(user:, source_id: nil, sources: nil)
      @sources = sources || self.class.sources_for(user).to_a
      @current = resolve_current(source_id)
      @index = @current ? @sources.index(@current) : 0
    end

    def total
      sources.size
    end

    def configured?(source = current)
      source.present? && source.recognition_configured?
    end

    # Cash never produces bank notifications: the wizard hides the email
    # criteria instead of asking for words that will never arrive.
    def email_applicable?
      current.present? && !current.cash?
    end

    # The words Yogasto already uses to understand this source in natural
    # language (confirmed keyword identifiers). Suggested/dismissed values are
    # not vocabulary yet.
    def alias_values
      return [] unless current

      current.recognition_identifiers
             .select { |identifier| identifier.confirmed? && identifier.keyword? }
             .sort_by(&:position)
             .map(&:value)
    end

    # Pending suggestions rendered as accept/dismiss chips. They are NOT
    # persisted by this read model: accepting one and saving goes through the
    # existing replace_identifiers flow.
    def suggestions
      return {} unless current

      @suggestions ||= SuggestionEngine.new(source: current).call
    end

    def last_four
      return @last_four if defined?(@last_four)

      @last_four = resolve_last_four
    end

    def email_preview
      return @email_preview if defined?(@email_preview)

      @email_preview = email_applicable? ? build_email_preview : nil
    end

    def whatsapp_example
      return nil unless current

      alias_value = alias_values.first.presence || current.name.downcase
      {
        channel: "whatsapp",
        label: I18n.t("money_sources.recognition.guided.whatsapp_channel"),
        text: I18n.t("money_sources.recognition.guided.example_whatsapp", alias: alias_value),
        highlight: alias_value
      }
    end

    def bank_group
      return @bank_group if defined?(@bank_group)

      @bank_group = current ? build_group(current) : nil
    end

    def bank_senders
      return @bank_senders if defined?(@bank_senders)

      @bank_senders = bank_group ? BankSetupWizard.confirmed_values(bank_group[:seed], %w[sender domain]) : []
    end

    def bank_subjects
      return @bank_subjects if defined?(@bank_subjects)

      @bank_subjects = bank_group ? BankSetupWizard.confirmed_values(bank_group[:seed], %w[subject header]) : []
    end

    private

    def resolve_current(source_id)
      return nil if sources.empty?

      sources.find { |source| source.id.to_s == source_id.to_s } || sources.first
    end

    def resolve_last_four
      return nil unless current

      raw = current.identifier.presence
      raw = current.credit_account&.card_last_four if raw.nil? && current.credit_card?
      MoneySource.last_four_from(raw)
    end

    # Sources sharing the same institution carry one seed with the bank-level
    # email configuration (senders/domains and subjects/headers). The grouping
    # key is the existing SourceRecognition::BankGrouping rule.
    def build_group(source)
      key = BankGrouping.key(source)
      members = sources.select { |candidate| BankGrouping.key(candidate) == key }
      {
        key: key,
        label: members.first.institution_name.presence ||
               I18n.t("money_sources.recognition.no_bank_group"),
        cash_only: members.all? { |member| member.cash? },
        seed: members.min_by { |member| [ member.created_at, member.id ] },
        members: members
      }
    end

    def build_email_preview
      group = bank_group
      body = email_body
      matched = alias_values.select { |value| body.downcase.include?(value.downcase) }
      fallback = fallback_highlight(body)

      {
        sender_name: group[:label],
        sender_address: bank_senders.first.presence ||
                        I18n.t("money_sources.recognition.guided.example_sender_fallback"),
        subject: bank_subjects.first.presence ||
                 I18n.t("money_sources.recognition.guided.example_subject"),
        body: body,
        # Always show at least one highlighted reference: configured criteria
        # when they appear in the sample, otherwise the source's last four or
        # name (both are real text in the sample).
        highlights: matched.presence || [ fallback ],
        fallback_highlight: fallback,
        configured_match: matched.any?
      }
    end

    def fallback_highlight(body)
      return last_four if last_four.present? && body.include?(last_four)

      current.name
    end

    def email_body
      if current.credit_card?
        return I18n.t("money_sources.recognition.guided.example_body_card",
                      name: current.name) if last_four.blank?

        I18n.t("money_sources.recognition.guided.example_body_card_digits",
               name: current.name, last_four: last_four)
      else
        I18n.t("money_sources.recognition.guided.example_body_account", name: current.name)
      end
    end
  end
end
