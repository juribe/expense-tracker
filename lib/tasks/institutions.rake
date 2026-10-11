# frozen_string_literal: true

# Controlled data migration tasks for the institution catalog. NEVER part of
# db:seed: these migrate user-owned data and must be run deliberately.
namespace :institutions do
  desc "Associate money sources with financial institutions from their legacy free-text bank. " \
       "DRY_RUN=1 previews without writing. Safe to re-run (already-associated sources are skipped)."
  task migrate_banks: :environment do
    Institutions::BankMigrator.run(dry_run: ENV.fetch("DRY_RUN", "0") == "1")
  end
end

  desc "Consolidate bank-level recognition values onto each bank group's seed source. " \
       "DRY_RUN=1 previews without writing. Safe to re-run (exact values are skipped, product keywords never move)."
  task consolidate_bank_recognition: :environment do
    Institutions::BankRecognitionConsolidator.run(dry_run: ENV.fetch("DRY_RUN", "0") == "1")
  end
