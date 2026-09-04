# frozen_string_literal: true

require "logger"

module Gmail
  # Synchronizes one Gmail connection: fetches new candidate emails, imports
  # each of them and records the outcome. Along the way, the cheap
  # SourceRecognition::DiscoveryService analyzes every fetched email to
  # propose Source Recognition suggestions (first sync = setup accelerator;
  # later syncs discover new recurring patterns incrementally). A failure on
  # a single email must never abort the whole synchronization.
  #
  #   summary = Gmail::SyncService.call(connection)
  #     => { fetched: 3, created: 2, ignored: 1, needs_review: 0, failed: 0,
  #          skipped: 0, suggestions: 2 }
  class SyncService
    MAX_MESSAGES_PER_SYNC = 25

    class << self
      def call(connection, client_class: Gmail::Client, extractor: nil, logger: Rails.logger)
        new(connection, client_class, extractor, logger).call
      end
    end

    def initialize(connection, client_class, extractor, logger)
      @connection = connection
      @client_class = client_class
      @extractor = extractor
      @logger = logger
    end

    def call
      return empty_summary unless @connection.active?

      messages = fetch_messages
      summary = import_all(messages)
      summary[:suggestions] = @suggestions_created

      @connection.update!(last_synced_at: Time.current)
      summary
    rescue Gmail::OauthClient::Error, Gmail::Client::Error => e
      @logger.error("[GmailSync] connection=#{@connection.id} api error: #{e.message}")
      empty_summary(error: e.message)
    end

    private

    def fetch_messages
      query = QueryBuilder.build(config: @connection.search_config_hash, last_synced_at: @connection.last_synced_at)
      client.list_messages(query: query, max_results: MAX_MESSAGES_PER_SYNC)
    end

    def client
      @client ||= @client_class.new(@connection)
    end

    def import_all(stubs)
      @suggestions_created = 0
      discovery = SourceRecognition::DiscoveryService.new(@connection.user)
      summary = { fetched: stubs.size, created: 0, ignored: 0, needs_review: 0, failed: 0, skipped: 0 }

      stubs.each do |stub|
        result = import_one(stub["id"], discovery)
        next unless result

        status_key = result.status == :processed ? :created : result.status
        summary[status_key] += 1 if summary.key?(status_key)
      end

      summary
    end

    def import_one(message_id, discovery)
      full_message = client.get_message(message_id)
      discover_for(full_message, discovery)
      result = importer.call(full_message)
      @logger.info(
        "[GmailSync] import message=#{message_id} status=#{result.status}" \
        " reason=#{result.reason.to_s[0, 80].inspect}"
      )
      result
    rescue StandardError => e
      @logger.error("[GmailSync] message=#{message_id} failed: #{e.class}: #{e.message}")
      mark_failed(message_id, "#{e.class}: #{e.message}")
      ExpenseImporter::Result.new(status: :failed, processed_email: nil, expense_ids: [], reason: nil)
    end

    # Cheap recognition discovery per message. Must never break the import
    # loop: any discovery failure is logged and skipped.
    def discover_for(message, discovery)
      result = discovery.process(message)
      @suggestions_created += result.suggestions_created if result
      @logger.info(
        "[GmailSync] discovery message=#{message[:id]} source=#{message[:from]}" \
        " subject=#{message[:subject].to_s[0, 60].inspect} lines=#{message[:body_text].to_s.lines.size}" \
        " passed=#{result && result.passed?} suggestions=#{result && result.suggestions_created}"
      )
    rescue StandardError => e
      @logger.warn("[GmailSync] discovery failed for message=#{message[:id]}: #{e.class}: #{e.message}")
    end

    # Records a retryable failure row when fetching/parsing blew up before the
    # importer could run, then reports it as :failed for the summary.
    def mark_failed(message_id, error_message)
      ProcessedEmail.find_or_initialize_by(provider: ExpenseImporter::PROVIDER, message_id: message_id.to_s).tap do |record|
        record.user ||= @connection.user
        record.status = "failed"
        record.failure_reason = error_message[0, 500]
        record.attempts += 1
        record.save!
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def importer
      @importer ||= begin
        options = { connection: @connection }
        options[:extractor] = @extractor if @extractor
        ExpenseImporter.new(**options)
      end
    end

    def empty_summary(error: nil)
      { fetched: 0, created: 0, ignored: 0, needs_review: 0, failed: 0, skipped: 0, suggestions: 0, error: error }.compact
    end
  end
end
