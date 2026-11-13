# frozen_string_literal: true

namespace :encryption do
  desc "Report rows stored as plaintext in Active Record encrypted columns"
  task report: :environment do
    rows = EncryptionBackfill.plaintext_rows

    puts "Plaintext rows: #{rows.size}"
    rows.each do |row|
      puts "  #{row[:model].name} id=#{row[:record].id} attribute=#{row[:attribute]}"
    end
  end

  desc "Re-encrypt plaintext rows (DRY_RUN=1 previews)"
  task backfill: :environment do
    if ENV["DRY_RUN"] == "1"
      puts "Would re-encrypt #{EncryptionBackfill.plaintext_rows.size} rows."
      next
    end

    puts "Re-encrypted #{EncryptionBackfill.run!} rows."
  end
end
