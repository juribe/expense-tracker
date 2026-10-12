# frozen_string_literal: true

module SourceRecognition
  # Reset
  # Controlled wipe of the user-owned recognition state so everyone starts
  # fresh with the new bank-group flow:
  #
  #   DRY_RUN=1 bin/rails recognition:reset_all   # preview only
  #   bin/rails recognition:reset_all
  #
  # What is cleared (ALL users):
  #   * MoneySourceRecognition + its identifiers (per-source keywords,
  #     senders, domains, subjects, both confirmed AND suggested rows).
  #   * Gmail connection search_config    (the fetched-email criteria:
  #     senders / domains / subject keywords).
  #   * Gmail connection setup_suggestions (the first-scan suggestion cache
  #     shown on the recognition page).
  #
  # What is NEVER touched:
  #   * OAuth state: connection rows, email, access/refresh tokens, expiry,
  #     active flag, sync state, last_synced_at.
  #   * processed_emails (import idempotence — re-running would duplicate
  #     historical email imports).
  #   * Money sources, their institution associations, transactions, expenses
  #     (financial data stays; only recognition RULES are wiped).
  #   * The global FinancialInstitution catalog (system-owned, used by the
  #     email filter).
  #
  # Re-running is harmless (nothing left to delete). NOT a seed.
  class Reset
    def self.run(dry_run: false)
      new(dry_run:).run
    end

    def initialize(dry_run: false)
      @dry_run = dry_run
    end

    def run
      # Counted in Ruby: the json columns cannot compare against '{}' in
      # SQL without casts, and connection counts are tiny.
      connections = GmailConnection.all.to_a
      counts = {
        recognitions: MoneySourceRecognition.count,
        identifiers: MoneySourceRecognitionIdentifier.count,
        search_config_cleared: connections.count { |connection| non_empty?(connection.search_config) },
        suggestions_cleared: connections.count { |connection| non_empty?(connection.setup_suggestions) }
      }

      unless @dry_run
        ActiveRecord::Base.transaction do
          MoneySourceRecognition.destroy_all
          GmailConnection.update_all(search_config: {}, setup_suggestions: {})
        end
      end

      summary(counts)
      counts
    end

    private

    def non_empty?(value)
      value.present? && value != {}
    end

    def summary(counts)
      puts
      puts "Recognition reset#{' (DRY RUN - nothing written)' if @dry_run}"
      puts "  recognition records deleted      : #{counts[:recognitions]}"
      puts "  recognition identifiers deleted  : #{counts[:identifiers]}"
      puts "  gmail search_config cleared      : #{counts[:search_config_cleared]}"
      puts "  gmail setup_suggestions cleared  : #{counts[:suggestions_cleared]}"
      puts "  kept: OAuth tokens, processed_emails, money sources, catalog"
      puts
    end
  end
end
