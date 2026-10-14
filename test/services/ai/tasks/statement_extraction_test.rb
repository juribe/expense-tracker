# frozen_string_literal: true

require "test_helper"

module Ai
  module Tasks
    class StatementExtractionTest < ActiveSupport::TestCase
      def window(text)
        StatementExtraction.new.send(:statement_window, text)
      end

      test "keeps the whole text when it fits under the limit" do
        text = "line\n" * 4_000 # ~ 20_000 chars

        assert_operator text.length, :<=, Ai::StatementExtractor::STATEMENT_CHAR_LIMIT
        assert_equal text, window(text)
      end

      test "keeps every transaction of an 18k-char statement" do
        middle = "05/09/2026       289241                                    $ 18.000        1/1"
        text = "#{"a" * 12_000}\n#{middle}\n#{"b" * 4_000}"

        assert_equal text, window(text)
        assert_includes window(text), middle
      end

      test "truncates only very long texts, keeping head and tail" do
        text = "#{"H" * 50_000}#{"T" * 50_000}"

        result = window(text)

        assert_operator result.length, :<, text.length
        assert result.start_with?("H" * Ai::StatementExtractor::STATEMENT_HEAD_CHARS)
        assert result.end_with?("T" * Ai::StatementExtractor::STATEMENT_TAIL_CHARS)
      end
    end
  end
end
