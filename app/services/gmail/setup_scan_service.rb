# frozen_string_literal: true

module Gmail
  # SetupScanService
  # The explicit "first sync as setup accelerator": scans the mailbox BROADLY
  # for bank/financial notification emails (NOT expense-merchant emails — no
  # import happens here, no AI is used) and produces exactly three kinds of
  # recognition output:
  #
  #   1. Sender recognition — bank senders/domains that recur as FINANCIAL
  #      notifications (advertising is rejected by
  #      SourceRecognition::FinancialEmailFilter before counting). Only
  #      senders seen on at least MIN_SENDER_EMAILS financial emails become
  #      reusable patterns; domains of passed financial emails are reusable
  #      by nature.
  #   2. Subject recognition — transactional catalog keywords plus recurring
  #      subject templates (SourceRecognition::SubjectTemplates), each stored
  #      with its occurrence count and institution when known. A subject seen
  #      once is never a pattern.
  #   3. Money source recognition — SourceRecognition::DiscoveryService runs
  #      per financial email exactly like during a normal sync, so the
  #      recognition page shows per-source suggestions to confirm.
  #
  # Every generated value is deduplicated against what the user already
  # USES (GmailConnection#search_config) or already CONFIRMED
  # (MoneySourceRecognitionIdentifier, status "confirmed") — regenerating
  # suggestions never re-proposes a known pattern.
  #
  # All three lists live on `setup_suggestions` and are reviewed on the
  # money source recognition page:
  #
  #   Gmail::SetupScanService.call(connection)
  #     => { scanned:, passed:, suggestions:, senders:, domains:,
  #          subject_keywords:, subject_templates: }
  class SetupScanService
    MAX_MESSAGES = 150
    MAX_SUGGESTIONS = 8
    LOOKBACK_DAYS = 180
    # A sender address pattern is only reusable after it recurs.
    MIN_SENDER_EMAILS = 2
    # A subject is only a pattern when it recurs.
    MIN_TEMPLATE_COUNT = 2

    EXCLUSIONS = [ "-category:promotions", "-category:social" ].freeze

    class << self
      def call(connection, client_class: Gmail::Client, logger: Rails.logger)
        new(connection, client_class, logger).call
      end
    end

    def initialize(connection, client_class, logger)
      @connection = connection
      @client_class = client_class
      @logger = logger
    end

    def call
      return empty_result unless @connection.active?

      messages = fetch_messages
      result = scan_all(messages)
      @connection.update!(setup_suggestions: result)
      @logger.info("[GmailSetup] connection=#{@connection.id} #{result.inspect}")
      result
    rescue Gmail::OauthClient::Error, Gmail::Client::Error => e
      @logger.error("[GmailSetup] connection=#{@connection.id} api error: #{e.message}")
      empty_result(error: e.message)
    end

    private

    # Broad scan: no from/subject clauses — the FinancialEmailFilter decides
    # which emails are bank notifications. Capped so huge mailboxes stay sane.
    def fetch_messages
      query = [ "newer_than:#{LOOKBACK_DAYS}d", *EXCLUSIONS ].join(" ")
      client.list_messages(query: query, max_results: MAX_MESSAGES)
    end

    def client
      @client ||= @client_class.new(@connection)
    end

    def scan_all(stubs)
      discovery = SourceRecognition::DiscoveryService.new(@connection.user)
      financial = []
      suggestions_created = 0

      stubs.each do |stub|
        message = client.get_message(stub["id"])
        filter_result = SourceRecognition::FinancialEmailFilter.call(message)
        next unless filter_result.passed?

        # BANK-ONLY criteria: sender/domain/subject suggestions come from
        # catalogued banks alone. Money source discovery still runs (it only
        # suggests against the user's own confirmed rules).
        if bank_email?(message, filter_result)
          suggestions_created += discover_for(message, discovery)
          financial << [ message, filter_result ]
        end
      rescue StandardError => e
        @logger.warn("[GmailSetup] message=#{stub['id']} skipped: #{e.class}: #{e.message}")
      end

      result = { scanned: stubs.size, passed: financial.size, suggestions: suggestions_created }
      result.merge(sender_recognition(financial))
            .merge(subject_recognition(financial))
    end

    # The email is bank-owned when the sender's domain is one of the
    # institution's official domains (mail.davibank.com → davibank.com) or
    # the From is itself the bank (display name/body alias, e.g. a
    # notification relay that still identifies the bank).
    def bank_email?(message, filter_result)
      institution = filter_result.institution
      return false unless institution

      domain = from_domain(message)
      return false if domain.blank?

      domain_institution = SourceRecognition::Catalog.match_domain(domain, domains_index)
      domain_institution == institution ||
        institution.folded_aliases.any? do |alias_word|
          SourceRecognition::TextNormalizer.contains_word?(message[:from].to_s, alias_word)
        end
    end

    def domains_index
      @domains_index ||= SourceRecognition::Catalog.domains_index(SourceRecognition::Catalog.institutions)
    end

    def from_domain(message)
      message[:from].to_s[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]&.split("@")&.last
    end

    # --- 1. sender recognition ------------------------------------------------

    # Groups the financial emails by sender identity (full address + domain).
    # The full address becomes a suggested pattern only when at least
    # MIN_SENDER_EMAILS financial emails share it; the domain is reusable
    # because the FinancialEmailFilter already proved each email is a
    # financial notification.
    def sender_recognition(financial)
      senders = Hash.new(0)
      domains = Hash.new(0)
      financial.each do |message, _|
        email = message[:from].to_s[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]
        next if email.blank?

        senders[email.downcase] += 1
        domains[email.split("@").last.downcase] += 1
      end

      {
        senders: suggested(senders, min: MIN_SENDER_EMAILS),
        domains: suggested(domains, min: 1)
      }
    end

    # --- 2. subject recognition -------------------------------------------------

    def subject_recognition(financial)
      keywords = Hash.new(0)
      templates = Hash.new { |h, key| h[key] = { value: nil, count: 0, institution: nil } }

      financial.each do |message, filter_result|
        count_transactional_keywords(message, filter_result, keywords)
        count_template(message, filter_result, templates)
      end

      {
        subject_keywords: suggested(keywords, min: 1),
        subject_templates: suggested_templates(templates)
      }
    end

    def count_transactional_keywords(message, filter_result, keywords)
      filter_result.subject_keywords.select(&:transactional?).each do |keyword|
        keywords[keyword.value] += 1
      end
    rescue StandardError => e
      @logger.warn("[GmailSetup] keyword aggregation failed for message=#{message[:id]}: #{e.message}")
    end

    def count_template(message, filter_result, templates)
      template = SourceRecognition::SubjectTemplates.template(message[:subject])
      return if template.blank?

      source = filter_result.institution
      key = SourceRecognition::SubjectTemplates.key(template)
      entry = templates[key]
      entry[:count] += 1
      entry[:value] ||= template
      # Prefer a concrete institution over a prior unknown one.
      if source && entry[:institution].blank?
        entry[:institution] = source.canonical_name
      end
    rescue StandardError => e
      @logger.warn("[GmailSetup] template aggregation failed for message=#{message[:id]}: #{e.message}")
    end

    def suggested_templates(templates)
      templates.values
               .select { |entry| entry[:count] >= MIN_TEMPLATE_COUNT }
               .reject { |entry| excluded?(entry[:value]) }
               .sort_by { |entry| [ -entry[:count], entry[:institution].to_s.downcase ] }
               .take(MAX_SUGGESTIONS)
               .map { |entry| { value: entry[:value], count: entry[:count], institution: entry[:institution] } }
    end

    # --- 3. money source recognition -------------------------------------------

    def discover_for(message, discovery)
      result = discovery.process(message)
      return 0 unless result

      result.suggestions_created
    rescue StandardError => e
      @logger.warn("[GmailSetup] discovery failed for message=#{message[:id]}: #{e.class}: #{e.message}")
      0
    end

    # dedup ----------------------------------------------------------------------

    def suggested(counter, min:)
      counter.select { |_, count| count >= min }
             .reject { |value, _| excluded?(value) }
             .sort_by { |_, count| -count }
             .first(MAX_SUGGESTIONS)
             .map { |value, count| { value: value, count: count } }
    end

    # A value the user already uses (Gmail search config) or already
    # confirmed (recognition identifiers) is never suggested again.
    def excluded?(value)
      known_values.include?(SourceRecognition::SubjectTemplates.key(value))
    end

    def known_values
      @known_values ||= begin
        config = @connection.search_config
        config = config.deep_symbolize_keys if config.is_a?(Hash)
        values = %i[senders domains subject_keywords].flat_map { |section| config[section].to_a }
        values.concat MoneySourceRecognitionIdentifier
                      .joins(money_source_recognition: :money_source).where(status: "confirmed")
                      .where(money_sources: { user_id: @connection.user_id })
                      .pluck(MoneySourceRecognitionIdentifier.table_name => :value)
        values.filter_map { |value| SourceRecognition::SubjectTemplates.key(value) if value.present? }.to_set
      end
    end

    def empty_result(error: nil)
      { scanned: 0, passed: 0, suggestions: 0, senders: [], domains: [], subject_keywords: [],
        subject_templates: [], error: error }.compact
    end
  end
end
