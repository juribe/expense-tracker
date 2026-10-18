# frozen_string_literal: true

module Ai
  module Tasks
    # Document-structure detection + transaction extraction for PDF statements.
    # Follows the standard cascade (cheap -> strong): the cheap model is tried
    # first and a confident result is accepted, while low-confidence (or
    # transaction-less) results escalate to the strong tier when it is
    # configured.
    #
    # input:  raw statement text
    # data:   { sources: [...], transactions: [...] } (see Ai::StatementExtractor)
    class StatementExtraction < Base
      def tiers
        %i[cheap strong]
      end

      def timeout
        40
      end

      def messages(input, context)
        [
          { role: "system", content: Ai::StatementExtractor.system_prompt(include_transactions: include_transactions?(context)) },
          { role: "user", content: "Statement contents:\n\n#{statement_window(input)}" }
        ]
      end

      def parse(content, input, context)
        include_transactions = include_transactions?(context)
        data = Ai::StatementExtractor.parse(parse_json(content), text: input,
                                                                  include_transactions: include_transactions)
        confidence = include_transactions ? mean_transaction_confidence(data) : source_confidence(data)
        { data: data, confidence: confidence }
      rescue Ai::StatementExtractor::ExtractionError => e
        raise InvalidResponse, e.message
      end

      private

      # The financial-setup wizard import only wants sources and balances, and
      # the review screen is the gate, so a source present is a strong enough
      # signal for a cheap-tier result when transactions are not extracted.
      def include_transactions?(context)
        context.key?(:include_transactions) ? context[:include_transactions] : true
      end

      def source_confidence(data)
        Array(data[:sources]).any? ? 1.0 : nil
      end

      def statement_window(text)
        str = text.to_s
        return str if str.length <= Ai::StatementExtractor::STATEMENT_CHAR_LIMIT

        "#{str[0, Ai::StatementExtractor::STATEMENT_HEAD_CHARS]}\n\n[...]\n\n#{str[-Ai::StatementExtractor::STATEMENT_TAIL_CHARS, Ai::StatementExtractor::STATEMENT_TAIL_CHARS]}"
      end

      def mean_transaction_confidence(data)
        confidences = Array(data[:transactions]).filter_map { |tx| tx[:confidence] }
        return nil if confidences.empty?

        confidences.sum / confidences.size
      end
    end
  end
end
