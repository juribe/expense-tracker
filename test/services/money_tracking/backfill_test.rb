# frozen_string_literal: true

require "test_helper"

module MoneyTracking
  class BackfillTest < ActiveSupport::TestCase
    test "assigns advanced to users with sources and simple to users without sources" do
      with_sources = existing_user("backfill_with_sources@example.com")
      source = with_sources.money_sources.create!(name: "Cuenta existente", kind: "account",
                                                 starting_balance: 100_000)
      without_sources = existing_user("backfill_without_sources@example.com")

      counts = Backfill.call(users: User.where(id: [ with_sources.id, without_sources.id ]))

      with_sources.reload
      without_sources.reload
      assert_equal({ detailed: 1, simple: 1, skipped: 0 }, counts)
      assert_equal "detailed", with_sources.money_tracking_mode
      assert_equal "simple", without_sources.money_tracking_mode
      assert with_sources.money_tracking_mode_selected?
      assert without_sources.money_tracking_mode_selected?
      assert_equal "account", with_sources.general_money_source.kind
      assert_equal "general", without_sources.general_money_source.kind
      assert MoneySource.exists?(source.id)
      assert_equal 100_000.to_d, source.reload.balance
    end

    test "is idempotent and does not create another General source" do
      user = existing_user("backfill_idempotent@example.com")
      Backfill.call(users: User.where(id: user.id))
      general_id = user.reload.general_money_source.id

      assert_no_difference "MoneySource.count" do
        counts = Backfill.call(users: User.where(id: user.id))
        assert_equal({ detailed: 0, simple: 0, skipped: 0 }, counts)
      end
      assert_equal general_id, user.reload.general_money_source.id
    end

    test "skips sign-up users that already own General" do
      user = User.create!(
        name: "Backfill Registration",
        email: "backfill_registration@example.com",
        password: "password123",
        registration_form: true,
        terms_accepted: "1",
        privacy_accepted: "1"
      )
      general_id = user.general_money_source.id

      assert_no_difference "MoneySource.count" do
        counts = Backfill.call(users: User.where(id: user.id))
        assert_equal({ detailed: 0, simple: 0, skipped: 1 }, counts)
      end
      assert_equal general_id, user.reload.general_money_source.id
    end

    private

    def existing_user(email)
      user = User.create!(name: "Backfill User", email: email, password: "password123")
      user.update_columns(money_tracking_mode: "detailed", money_tracking_mode_selected_at: nil)
      user
    end
  end
end
