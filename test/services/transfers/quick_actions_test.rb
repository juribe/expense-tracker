# frozen_string_literal: true

require "test_helper"

module Transfers
  class QuickActionsTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Quick Actions User", email: "quick_actions_test@example.com", password: "password123")
      @account = @user.money_sources.create!(name: "Cuenta", kind: "account")
      @debit = @user.money_sources.create!(name: "Débito", kind: "debit_card")
      @wallet = @user.money_sources.create!(name: "Nequi", kind: "wallet")
      @cash = @user.money_sources.create!(name: "Efectivo", kind: "cash")
      @card = @user.money_sources.create!(name: "Visa", kind: "credit_card")
      @revolving = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving")
      @personal = @user.money_sources.create!(name: "Libre Inversión", kind: "loan", sub_kind: "personal")
      @pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket")
    end

    def modes_for(source, cash_available: true)
      Transfers::QuickActions.for(source, cash_available: cash_available).map { |action| action[:mode] }
    end

    test "accounts, debit cards and wallets offer withdraw, transfer and pocket" do
      assert_equal %w[withdraw transfer pocket], modes_for(@account)
      assert_equal %w[withdraw transfer pocket], modes_for(@debit)
      assert_equal %w[withdraw transfer pocket], modes_for(@wallet)
    end

    test "payment origins drop the withdraw action without a cash source" do
      assert_equal %w[transfer pocket], modes_for(@account, cash_available: false)
    end

    test "cash offers deposit (transfer mode) and pocket" do
      assert_equal %w[transfer pocket], modes_for(@cash)
    end

    test "credit cards offer only the advance" do
      assert_equal %w[advance], modes_for(@card)
    end

    test "pockets offer only the release" do
      assert_equal %w[release], modes_for(@pocket)
    end

    test "revolving loans offer only the disbursement" do
      assert_equal %w[disburse], modes_for(@revolving)
    end

    test "non-revolving loans offer nothing" do
      assert_empty Transfers::QuickActions.for(@personal)
    end

    test "inactive sources offer nothing" do
      @account.update!(active: false)
      assert_empty Transfers::QuickActions.for(@account)
    end

    test "nil sources offer nothing" do
      assert_empty Transfers::QuickActions.for(nil)
    end

    test "every action carries a title and an icon" do
      Transfers::QuickActions.for(@account).each do |action|
        assert action[:title].present?
        assert action[:icon].present?
      end
    end
  end
end
