# frozen_string_literal: true

module MailInbound
  # Processor
  # Adapts a normalized inbound email to the existing Gmail import pipeline.
  class Processor
    Connection = Struct.new(:user)

    def initialize(user:, provider:, source: nil, importer: nil, detector: nil, extractor: nil)
      @user = user
      @provider = provider.to_s
      @source = (source || provider).to_s
      @importer = importer
      @detector = detector
      @extractor = extractor
    end

    def call(message)
      raise ArgumentError, "message is required" if message.blank?

      normalized = normalize(message)
      if MailInbound::ForwardingVerificationDetector.verification_message?(normalized)
        MailInbound::ForwardingVerificationDetector.store!(user: @user, message: normalized)
        return Gmail::ExpenseImporter::Result.new(
          status: :ignored, processed_email: nil, expense_ids: [], reason: "gmail forwarding verification"
        )
      end

      importer.call(normalized)
    end

    private

    def importer
      @importer ||= Gmail::ExpenseImporter.new(**importer_options)
    end

    def importer_options
      options = {
        connection: Connection.new(@user),
        provider: @provider,
        source: @source
      }
      options[:detector] = @detector if @detector
      options[:extractor] = @extractor if @extractor
      options
    end

    def normalize(message)
      normalized = message.to_h.symbolize_keys
      normalized[:id] ||= normalized[:external_id]
      normalized[:internal_date] = parse_date(normalized[:internal_date]) if normalized[:internal_date].present?
      normalized
    end

    def parse_date(value)
      return value if value.is_a?(Time) || value.is_a?(Date)

      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError, TypeError
      Time.current
    end
  end
end
