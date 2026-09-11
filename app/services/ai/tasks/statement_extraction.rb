# frozen_string_literal: true

module Ai
  module Tasks
    # Document-structure detection + transaction extraction for PDF statements.
    # Requires real document reasoning, so it always goes straight to the
    # strong tier — a cheap model is never trusted with whole statements.
    #
    # input:  raw statement text
    # data:   { sources: [...], transactions: [...] } (see Ai::StatementExtractor)
    class StatementExtraction < Base
      def tiers
        %i[strong]
      end

      def timeout
        40
      end

      def messages(input, _context)
        [
          { role: "system", content: Ai::StatementExtractor.system_prompt },
          { role: "user", content: "Statement contents:\n\n#{statement_window(input)}" }
        ]
      end

      def parse(content, input, _context)
        data = Ai::StatementExtractor.parse(parse_json(content), text: input)
        { data: data, confidence: mean_transaction_confidence(data) }
      rescue Ai::StatementExtractor::ExtractionError => e
        raise InvalidResponse, e.message
      end

      private

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
