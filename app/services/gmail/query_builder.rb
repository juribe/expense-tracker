# frozen_string_literal: true

module Gmail
  # Builds the Gmail search query used to find candidate transaction emails
  # from configurable criteria (senders, sender domains, subject keywords).
  #
  #   Gmail::QueryBuilder.build(config: { senders: ["notifications@bank.com"],
  #                                       subject_keywords: ["compra", "pago"] },
  #                             last_synced_at: connection.last_synced_at)
  #   => 'from:(notifications@bank.com) subject:(compra OR pago) newer_than:9d -category:promotions'
  class QueryBuilder
    DEFAULT_SUBJECT_KEYWORDS = %w[
      compra compró transacción transaccion pago cobro cargo débito debito
      purchase transaction payment charged
    ].freeze

    DEFAULT_LOOKBACK_DAYS = 15
    OVERLAP_BUFFER_DAYS = 2
    MAX_LOOKBACK_DAYS = 180

    EXCLUSIONS = [ "-category:promotions", "-category:social" ].freeze

    class << self
      def build(config:, last_synced_at: nil)
        new(config, last_synced_at).build
      end
    end

    def initialize(config, last_synced_at)
      @config = config.is_a?(Hash) ? config.deep_symbolize_keys : {}
      @last_synced_at = last_synced_at
    end

    def build
      parts = []
      parts << from_clause if from_values.any?
      parts << subject_clause
      parts << "newer_than:#{lookback_days}d"
      parts.concat(EXCLUSIONS)
      parts.join(" ")
    end

    private

    def senders
      Array(@config[:senders]).map(&:strip).reject(&:blank?)
    end

    def domains
      Array(@config[:domains]).map(&:strip).reject(&:blank?)
    end

    def subject_keywords
      keywords = Array(@config[:subject_keywords]).map(&:strip).reject(&:blank?)
      keywords.any? ? keywords : DEFAULT_SUBJECT_KEYWORDS
    end

    def from_values
      senders + domains
    end

    def from_clause
      "from:(#{from_values.join(' OR ')})"
    end

    def subject_clause
      "subject:(#{subject_keywords.join(' OR ')})"
    end

    # Look back a bit further than the last sync so border-line messages are
    # not missed; duplicates are prevented by ProcessedEmail anyway.
    def lookback_days
      configured = @config[:lookback_days].to_i
      return clamp_lookback(configured) if configured.positive?

      return DEFAULT_LOOKBACK_DAYS + OVERLAP_BUFFER_DAYS if @last_synced_at.blank?

      elapsed = (Time.current - @last_synced_at) / 1.day
      clamp_lookback(elapsed.ceil + OVERLAP_BUFFER_DAYS)
    end

    def clamp_lookback(days)
      days.clamp(1, MAX_LOOKBACK_DAYS)
    end
  end
end
