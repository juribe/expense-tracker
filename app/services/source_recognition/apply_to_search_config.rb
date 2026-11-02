# frozen_string_literal: true

module SourceRecognition
  # ApplyToSearchConfig
  # Feeds CONFIRMED recognition values back into every one of the user's Gmail
  # connection search configs so the next sync scopes its Gmail query to the
  # confirmed bank senders / domains / subject keywords instead of the generic
  # defaults. The dispatcher syncs all active connections, so all of them must
  # stay in sync with the user-level recognition rules.
  #
  # This is the "first sync as setup accelerator" feedback loop: discovery
  # proposes suggestions, the user confirms them on the recognition page, and
  # confirmation here narrows what Gmail sync fetches going forward.
  #
  #   SourceRecognition::ApplyToSearchConfig.call(user:)
  #
  # Mapping (confirmed identifiers -> search_config):
  #   keyword / subject / header  -> subject_keywords
  #   sender                      -> senders
  #   domain                      -> domains
  #
  # Only CONFIRMED values participate; suggestions never leak into the query.
  class ApplyToSearchConfig
    SECTION_KIND_MAP = {
      senders: %w[sender],
      domains: %w[domain],
      subject_keywords: %w[keyword subject header]
    }.freeze

    class << self
      def call(user:)
        new(user).call
      end
    end

    def initialize(user)
      @user = user
    end

    def call
      connections = user.gmail_connections.to_a
      return false if connections.empty?

      sections = confirmed_sections
      connections.each { |connection| merge_into(connection, sections) }
      true
    end

    private

    attr_reader :user

    def confirmed_sections
      categories = SECTION_KIND_MAP.keys.to_h { |section| [ section, [] ] }
      confirmed_values.each do |kind, value|
        SECTION_KIND_MAP.each do |section, kinds|
          categories[section] << value if kinds.include?(kind)
        end
      end
      categories
    end

    def confirmed_values
      MoneySourceRecognitionIdentifier
        .joins(money_source_recognition: :money_source)
        .where(money_sources: { user_id: user.id, kind: MoneySource::PAYMENT_KINDS })
        .where(status: "confirmed")
        .pluck(:kind, :value)
    end

    # Union the confirmed values with any pre-existing config for each section
    # (never drop what was already set), preserving other keys.
    def merge_into(connection, sections)
      base = connection.search_config.is_a?(Hash) ? connection.search_config.deep_symbolize_keys : {}

      merged = SECTION_KIND_MAP.keys.each_with_object({}) do |section, acc|
        existing = Array(base[section]).map(&:to_s).map(&:strip).reject(&:blank?)
        added = sections.fetch(section).map(&:to_s).map(&:strip).reject(&:blank?)
        acc[section] = (existing + added).uniq
      end

      connection.update!(search_config: base.merge(merged))
    end
  end
end
