# frozen_string_literal: true

module Gmail
  # SetupScanService
  # The explicit "first sync as setup accelerator": scans the mailbox BROADLY
  # for bank/financial notification emails (NOT expense-merchant emails — no
  # import happens here) and produces two kinds of output:
  #
  #   1. Gmail settings suggestions (senders, domains, subject keywords) —
  #      aggregated from the financial emails found, persisted on the
  #      connection's setup_suggestions so the setup page can prefill the
  #      search config form for the user to confirm (step 1 of the wizard).
  #   2. Money source suggestions — SourceRecognition::DiscoveryService runs
  #      per financial email exactly like during a normal sync, so the
  #      recognition page shows what to confirm (step 2 of the wizard).
  #
  #   Gmail::SetupScanService.call(connection)
  #     => { scanned: 150, passed: 34, suggestions: 12, senders: [...], ... }
  class SetupScanService
    MAX_MESSAGES = 150
    MAX_SUGGESTIONS = 8
    LOOKBACK_DAYS = 180
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
      senders = Hash.new(0)
      domains = Hash.new(0)
      subject_keywords = Hash.new(0)
      result = { scanned: stubs.size, passed: 0, suggestions: 0 }

      stubs.each do |stub|
        message = client.get_message(stub["id"])
        filter_result = SourceRecognition::FinancialEmailFilter.call(message)
        next unless filter_result.passed?

        result[:passed] += 1
        aggregate_settings(message, filter_result, senders, domains, subject_keywords)
        result[:suggestions] += discover_for(message, discovery)
      rescue StandardError => e
        @logger.warn("[GmailSetup] message=#{stub['id']} skipped: #{e.class}: #{e.message}")
      end

      result.merge(
        senders: top(senders),
        domains: top(domains),
        subject_keywords: top(subject_keywords)
      )
    end

    # Count the sender identity (full address + domain) and the transactional
    # catalog keywords actually present in the subject. Subject keywords are
    # deliberately catalog-scoped: high precision, no per-email noise.
    def aggregate_settings(message, filter_result, senders, domains, subject_keywords)
      email = message[:from].to_s[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]
      return if email.blank?

      senders[email.downcase] += 1
      domains[email.split("@").last.downcase] += 1

      filter_result.subject_keywords.select(&:transactional?).each do |keyword|
        subject_keywords[keyword.value] += 1
      end
    end

    def discover_for(message, discovery)
      result = discovery.process(message)
      return 0 unless result

      result.suggestions_created
    rescue StandardError => e
      @logger.warn("[GmailSetup] discovery failed for message=#{message[:id]}: #{e.class}: #{e.message}")
      0
    end

    def top(counter)
      counter.sort_by { |_, count| -count }.first(MAX_SUGGESTIONS)
             .map { |value, count| { value: value, count: count } }
    end

    def empty_result(error: nil)
      { scanned: 0, passed: 0, suggestions: 0, senders: [], domains: [], subject_keywords: [],
        error: error }.compact
    end
  end
end
