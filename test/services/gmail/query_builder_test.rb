# frozen_string_literal: true

require "test_helper"

module Gmail
  class QueryBuilderTest < ActiveSupport::TestCase
    def build(config, last_synced_at: nil)
      Gmail::QueryBuilder.build(config: config, last_synced_at: last_synced_at)
    end

    test "uses default subject keywords when none configured" do
      query = build({})
      assert_includes query, "subject:(compra OR compró OR transacción OR transaccion OR pago"
      assert_match(/newer_than:\d+d/, query)
    end

    test "includes configured senders and domains in the from clause" do
      query = build({ senders: [ "notifications@bank.com" ], domains: [ "cards.bank.com" ] })
      assert_includes query, "from:(notifications@bank.com OR cards.bank.com)"
    end

    test "omits from clause when no senders configured" do
      refute build({}).include?("from:")
    end

    test "computes lookback from last sync plus overlap buffer" do
      last_sync = 3.days.ago
      query = build({}, last_synced_at: last_sync)
      assert_includes query, "newer_than:6d"
    end

    test "clamps lookback between 1 and 180 days" do
      assert_includes build({ lookback_days: 0 }, last_synced_at: 500.days.ago), "newer_than:180d"
      assert_includes build({ lookback_days: 400 }), "newer_than:180d"
      assert_includes build({ lookback_days: 2 }, last_synced_at: 500.days.ago), "newer_than:2d"
    end

    test "excludes noisy categories" do
      query = build({})
      assert_includes query, "-category:promotions"
      assert_includes query, "-category:social"
    end
  end
end
