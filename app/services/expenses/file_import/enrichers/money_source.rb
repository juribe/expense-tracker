# frozen_string_literal: true

module Expenses
  module FileImport
    module Enrichers
      # Money source linking. Resolution priority: keyword detection over the
      # transaction description (reused across equal activities within the
      # import, flagged as reused_in_import) wins; the statement-level source
      # (verified by its account/card number) is assigned to everything else
      # so a statement import never lands unlinked.
      class MoneySource
        include Expenses::ValueParsing

        def initialize(user:)
          @user = user
        end

        def call(candidates, sources = [])
          statement_source = statement_money_source(sources)
          detector = MoneySources::Detector.new(user: @user)
          resolved = {}
          candidates.each do |candidate|
            activity = candidate.description.to_s
            key = normalize_name(activity) || activity.presence
            found = detected_from_cache = nil
            if resolved.key?(key)
              found = resolved[key]
              detected_from_cache = found.present?
            else
              found = detect_money_source(detector, activity)
              resolved[key] = found
            end

            if found
              candidate.money_source_id = found.id
              candidate.money_source_name = found.name
              candidate.money_source_source = detected_from_cache ? "reused_in_import" : "detected"
            elsif statement_source
              candidate.money_source_id = statement_source.id
              candidate.money_source_name = statement_source.name
              candidate.money_source_source = "statement"
            else
              candidate.money_source_source = "missing"
            end
          end
          candidates
        end

        private

        def detect_money_source(detector, text)
          detector.call(text)
        rescue StandardError
          nil
        end

        # Matches the statement's extracted source against the user's own sources
        # (verified by the account/card last four, else by a unique bank+kind
        # match), so every candidate inherits the owning source even when no
        # transaction description mentions a keyword.
        def statement_money_source(sources)
          Array(sources).filter_map do |statement|
            by_statement_identifier(statement) || by_statement_bank_and_kind(statement)
          end.first
        end

        def by_statement_identifier(statement)
          digits = (statement.identifier.presence || statement.card_last_four.presence).to_s.gsub(/\D/, "")
          last4 = digits[-4..]
          return nil unless last4&.length == 4

          match = MoneySources::Match.call(user: @user, card_last_four: last4)
          match if match.is_a?(MoneySource)
        end

        def by_statement_bank_and_kind(statement)
          bank = statement.bank.to_s.strip
          kind = statement.kind.to_s
          return nil if bank.blank? || kind.blank?

          matches = @user.money_sources.active.select do |source|
            source.kind == kind && normalize_name(source.bank) == normalize_name(bank)
          end
          matches.one? ? matches.first : nil
        end
      end
    end
  end
end
