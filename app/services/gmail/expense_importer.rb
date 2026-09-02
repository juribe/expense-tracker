# frozen_string_literal: true

module Gmail
  # Processes ONE email message through the import pipeline:
  # dedup check -> transaction detection -> AI extraction -> validation ->
  # expense creation (or review queue) -> mark as processed.
  #
  # Every outcome is recorded in ProcessedEmail so the same Gmail message can
  # never generate more than one import.
  #
  #   Gmail::ExpenseImporter.new(connection: connection).call(message)
  class ExpenseImporter
    AUTO_CREATE_THRESHOLD = 0.75
    PROVIDER = "gmail"

    Result = Struct.new(:status, :processed_email, :expense_ids, :reason, keyword_init: true)

    def initialize(connection:, detector: EmailTransactionDetector.new, extractor: Ai::TransactionExtractor.new)
      @connection = connection
      @detector = detector
      @extractor = extractor
    end

    # `message` is the normalized hash produced by Gmail::Client#get_message:
    #   { id:, from:, subject:, body_text:, internal_date:, snippet:, headers: }
    def call(message)
      @message_id = message[:id].to_s
      return skipped("already processed") if already_processed?

      detection = @detector.call(subject: message[:subject], body: message[:body_text])
      unless detection.transactional?
        return record!(:ignored, reason: detection.reason)
      end

      # Email-level source recognition (senders/domains/subjects/keywords).
      # Runs once per message; per-transaction matching may still disambiguate
      # using the AI-extracted card digits.
      @recognition = SourceRecognition::Matcher.call(user: @connection.user, message: message)

      process_extraction(message)
    end

    private

    def already_processed?
      # Failed rows stay retryable: only terminal outcomes block reprocessing.
      ProcessedEmail.where(provider: PROVIDER, message_id: @message_id)
                    .where.not(status: "failed")
                    .exists?
    end

    def process_extraction(message)
      extraction = @extractor.call(
        subject: message[:subject],
        body: message[:body_text],
        today: (message[:internal_date] || Time.current).to_date
      )
      return record!(:failed, reason: extraction[:error]) unless extraction[:ok?]

      data = extraction[:data]
      return record!(:ignored, reason: data[:reason].presence || "not a transaction email") if data[:should_ignore]

      handle_transactions(data)
    end

    def handle_transactions(data)
      transactions = data[:transactions]
      min_confidence = transactions.map { |t| t[:confidence].to_f }.min || 0.0

      if min_confidence < AUTO_CREATE_THRESHOLD
        return record!(
          :needs_review,
          payload: { subject: @subject, transactions: transactions },
          reason: "confidence below #{AUTO_CREATE_THRESHOLD}"
        )
      end

      create_expenses(transactions)
    end

    def create_expenses(transactions)
      expense_ids = []
      skipped_types = []

      ActiveRecord::Base.transaction do
        transactions.each do |transaction|
          unless transaction[:type] == "expense"
            skipped_types << "#{transaction[:type]} from #{transaction[:merchant]}"
            next
          end

        matched = resolve_money_source(transaction)
        # Match returns an array when several sources share the tag. Do not
        # auto-assign: leave the expense without a source for manual review.
        money_source = matched if matched.is_a?(MoneySource)

          expense_ids << Expenses::Create.call(
            user: @connection.user,
            amount: transaction[:amount],
            description: transaction[:merchant],
            category: transaction[:category],
            occurred_at: Time.zone.parse(transaction[:occurred_at]),
            source: :gmail,
            gmail_message_id: @message_id,
            money_source: money_source
          ).id
        end
      end

      reason = skipped_types.any? ? "skipped non-expense entries: #{skipped_types.join(', ')}" : nil
      record!(:processed, expense_ids: expense_ids, reason: reason)
    rescue Expenses::Create::Invalid, ActiveRecord::RecordInvalid => e
      record!(:failed, reason: e.message)
    end

    # Source resolution precedence for a transaction:
    #   1. Email-level recognition with a single winner -> that source.
    #   2. Recognition ambiguous (several candidates of the same bank) ->
    #      the AI-extracted card last-four disambiguates when exactly one
    #      candidate's last_four matches.
    #   3. Legacy tag matching (MoneySources::Match) — sources without
    #      recognition config keep working through their tags.
    #   Returns a MoneySource or nil (nil/array => no auto-assignment).
    def resolve_money_source(transaction)
      return @recognition if @recognition.is_a?(MoneySource)

      if @recognition.is_a?(Array) && transaction[:card_last_four].present?
        target = transaction[:card_last_four].to_s.scan(/\d/).join[-4..]
        disambiguated = @recognition.select { |source| source.last_four == target }
        return disambiguated.first if disambiguated.one?
      end

      matched = MoneySources::Match.call(
        user: @connection.user,
        card_last_four: transaction[:card_last_four],
        bank: transaction[:bank]
      )
      matched if matched.is_a?(MoneySource)
    end

    def record!(status, expense_ids: [], reason: nil, payload: nil)
      processed_email = ProcessedEmail.find_or_initialize_by(provider: PROVIDER, message_id: @message_id)
      processed_email.user ||= @connection.user
      processed_email.status = status.to_s
      processed_email.expense_id = expense_ids.first
      processed_email.failure_reason = reason.presence
      processed_email.payload = payload ? JSON.generate(payload) : processed_email.payload
      processed_email.attempts += 1
      processed_email.processed_at = Time.current
      processed_email.save!

      Result.new(status: status.to_sym, processed_email: processed_email, expense_ids: expense_ids, reason: reason)
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def skipped(reason)
      Result.new(status: :skipped, processed_email: nil, expense_ids: [], reason: reason)
    end
  end
end
