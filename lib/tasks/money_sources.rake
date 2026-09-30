# frozen_string_literal: true

namespace :money_sources do
  desc "Rebuild cached_balance for all money sources from scratch (backfill / drift repair)"
  task rebuild_balances: :environment do
    total = MoneySource.count
    MoneySource.find_each.with_index(1) do |source, index|
      MoneySources::BalanceSync.rebuild!(source)
      puts "[#{index}/#{total}] #{source.name}: #{source.balance}"
    end
    puts "Done. Rebuilt #{total} money sources."
  end
end
