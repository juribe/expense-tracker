# frozen_string_literal: true

module Expenses
  module FileImport
    # Shapes parsed rows / AI transactions into valid ExpenseCandidates.
    # Resolution work that repeats across rows (RowResolver calls, category
    # loading) goes through the ImportContext caches; the resolver layer
    # cleans the description, re-derives free-text rows and attaches review
    # warnings.
    class CandidateBuilder
      include Expenses::ValueParsing

      def initialize(context:)
        @context = context
      end

      # Deterministic rows: map the amount column, resolve the row once per
      # unique activity through RowResolver, and keep only valid candidates.
      def from_tabular_rows(rows, mapping)
        rows.filter_map do |row|
          candidate = tabular_candidate(row, mapping)
          candidate&.valid? ? candidate : nil
        end
      end

      # AI statement extractor transactions.
      def from_transactions(transactions)
        categories = @context.categories

        transactions.filter_map do |tx|
          next unless tx.is_a?(Hash)

          tx = tx.transform_keys(&:to_s)
          description = tx["description"].to_s.strip
          amount = parse_amount(tx["amount"])
          next if description.blank? || amount.nil?

          category_name = tx["category"].to_s.strip.presence || "Others"
          category = resolve_category(categories, category_name)

          ExpenseCandidate.new(
            user: @context.user,
            amount: amount.abs,
            currency: ExpenseCandidate::DEFAULT_CURRENCY,
            category_id: category&.id,
            category_name: category&.name || category_name,
            description: description,
            merchant: nil,
            date: parse_date(tx["date"]),
            source: "playground_file",
            confidence: normalize_confidence(tx["confidence"]),
            money_source_id: nil,
            money_source_name: nil
          )
        end
      end

      def statements(sources_data)
        sources_data.map { |data| ParsedStatement.new(data) }
      end

      private

      def tabular_candidate(row, mapping)
        amount_source = amount_cell(row, mapping)
        return if amount_source.blank?

        amount = parse_amount(amount_source)
        return if amount.nil?

        description = cell_text(mapping.description && row[mapping.description])
        return if description.blank?

        row_date = parse_date(cell_text(mapping.date && row[mapping.date]))

        # The resolver layer cleans the description, re-derives free-text
        # rows and attaches review warnings; repeated row names resolve once
        # per import and reuse the whole resolution.
        key = @context.activity_key(description)
        resolved = @context.row_cache[key] ||= Expenses::RowResolver.call(
          user: @context.user,
          description: description,
          amount: amount.abs,
          date: row_date,
          categories: @context.categories,
          money_source_detector: @context.money_source_detector
        )

        candidate = ExpenseCandidate.new(
          user: @context.user,
          amount: resolved.amount || amount.abs,
          currency: ExpenseCandidate::DEFAULT_CURRENCY,
          category_id: nil,
          category_name: "Others",
          description: resolved.description,
          merchant: nil,
          date: resolved.date || row_date,
          source: "playground_file",
          confidence: 0.9,
          money_source_id: nil,
          money_source_name: nil
        )
        candidate.warnings = resolved.warnings
        candidate
      end

      # Picks the row cell that carries the transaction's absolute amount.
      # When the statement splits debits and credits into separate columns,
      # the dedicated debit column (expense_only) is authoritative; otherwise
      # the first cell that parses as a non-zero amount.
      def amount_cell(row, mapping)
        return row[mapping.amount] if mapping.amount.present?

        row.to_a.find { |cell| parse_amount(cell_text(cell)) }
      end

      def cell_text(value)
        value.to_s.strip.presence
      end

      def resolve_category(categories, name)
        normalized = normalize_name(name)
        categories.find { |c| normalize_name(c.name) == normalized } ||
          categories.find { |c| normalize_name(c.name).include?(normalized) || normalized.include?(normalize_name(c.name)) }
      end
    end
  end
end
