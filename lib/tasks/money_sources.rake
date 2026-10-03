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

  desc "Replay usage expenses into outstanding_balance for revolving loans (idempotent, re-runnable)"
  task rebuild_revolving_outstanding: :environment do
    sources = MoneySource.where(kind: "loan", sub_kind: "revolving")
    sources.find_each.with_index(1) do |source, index|
      before = source.credit_account&.outstanding_balance.to_d
      MoneySources::OutstandingSync.backfill!(source)
      source.reload
      puts "[#{index}/#{sources.count}] #{source.name}: #{before} -> #{source.credit_account.outstanding_balance}"
    end
    puts "Done."
  end
end
