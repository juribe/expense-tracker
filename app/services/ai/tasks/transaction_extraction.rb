# frozen_string_literal: true

module Ai
  module Tasks
    # Email transaction extraction (bank / card notification emails). Emails
    # mix marketing, alerts and real transactions, so they are classified by
    # the strong tier.
    #
    # input:   { subject:, body: }
    # context: { today: Date }
    # data:    { transactions:, should_ignore:, reason: } (see Ai::TransactionExtractor)
    class TransactionExtraction < Base
      def tiers
        %i[strong]
      end

      def messages(input, _context)
        [
          { role: "system", content: Ai::TransactionExtractor.system_prompt },
          { role: "user", content: email_content(input) }
        ]
      end

      def parse(content, _input, context)
        data = Ai::TransactionExtractor.parse(parse_json(content), today: context[:today] || Date.current)
        confidences = Array(data[:transactions]).filter_map { |tx| tx[:confidence] }
        { data: data, confidence: confidences.empty? ? nil : (confidences.sum / confidences.size) }
      rescue Ai::TransactionExtractor::ExtractionError => e
        raise InvalidResponse, e.message
      end

      private

      def email_content(input)
        <<~CONTENT
          Email subject: #{input[:subject].to_s[0, 200]}
          Email body:
          #{input[:body].to_s[0, 6000]}
        CONTENT
      end
    end
  end
end
