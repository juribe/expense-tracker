# frozen_string_literal: true

module Expenses
  module FileImport
    # Per-import shared state. Every cross-row cache lives here so repeated
    # rows reuse the work of the first one: RowResolver results, the money
    # source detector and memoized category lists. One instance per import;
    # never per row.
    class ImportContext
      attr_reader :user, :row_cache, :money_source_cache

      def initialize(user)
        @user = user
        @row_cache = {}
        @money_source_cache = {}
      end

      def categories
        @categories ||= Category.for_user(user).order(:name).to_a
      end

      def expense_categories
        @expense_categories ||= Category.for_user(user).where(category_type: "expense").order(:name).to_a
      end

      def money_source_detector
        @money_source_detector ||= MoneySources::Detector.new(user: user)
      end

      # Cache key shared by every per-import layer (row resolution,
      # classification, money source detection).
      def activity_key(description)
        ActivityClassification.normalize_name(description) || description
      end
    end
  end
end
