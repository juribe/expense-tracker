# frozen_string_literal: true

require "test_helper"

module MoneySources
  class BalanceSyncTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Test User", email: "balance_sync_test@example.com", password: "password123")
      @category = Category.create!(name: "Food #{Time.now.to_i}")
    end

    def create_source(**overrides)
      @user.money_sources.create!(
        { name: "Savings Account #{Time.now.to_i}", kind: "account", starting_balance: 1000 }.merge(overrides)
      )
    end

    def create_expense(source, amount)
      source.transactions.create!(user: @user, category: @category, amount: -amount, date: Date.today, kind: "expense", source: "manual")
    end

    def create_income(source, amount)
      source.transactions.create!(user: @user, category: @category, amount: amount, date: Date.today, kind: "income", source: "manual")
    end

    test "creating an expense updates the cached balance" do
      source = create_source

      assert_difference -> { source.reload.cached_balance }, -30 do
        create_expense(source, 30)
      end
    end

    test "creating an income updates the cached balance" do
      source = create_source

      assert_difference -> { source.reload.cached_balance }, 200 do
        create_income(source, 200)
      end
    end

    test "expense without money source does not change any cached balance" do
      source = create_source

      assert_no_difference -> { source.reload.cached_balance } do
        Transaction.create!(user: @user, category: @category, amount: -10, date: Date.today, kind: "expense", source: "manual")
      end
    end

    test "destroying an expense reverses the cached balance" do
      source = create_source
      expense = create_expense(source, 40)

      assert_difference -> { source.reload.cached_balance }, 40 do
        expense.destroy!
      end
    end

    test "updating expense amount updates the cached balance by the difference" do
      source = create_source
      expense = create_expense(source, 50)

      assert_difference -> { source.reload.cached_balance }, 20 do
        expense.update!(amount: 30)
      end
    end

    test "changing the money source moves the delta between sources" do
      old_source = create_source(name: "Old #{Time.now.to_i}")
      new_source = create_source(name: "New #{Time.now.to_i}")
      expense = create_expense(old_source, 25)

      assert_difference -> { new_source.reload.cached_balance }, -25 do
        assert_difference -> { old_source.reload.cached_balance }, 25 do
          expense.update!(money_source: new_source)
        end
      end
    end

    test "debit card transaction rolls up to the parent account cache" do
      account = create_source(name: "Checking #{Time.now.to_i}")
      card = create_source(name: "Debit Card #{Time.now.to_i}", kind: "debit_card", parent: account, starting_balance: 0)

      assert_difference -> { account.reload.cached_balance }, -30 do
        assert_no_difference -> { card.reload.cached_balance } do
          create_expense(card, 30)
        end
      end
    end

    test "credit card transaction updates the card cache (negative debt)" do
      cc = create_source(name: "Visa #{Time.now.to_i}", kind: "credit_card", starting_balance: 0)

      assert_difference -> { cc.reload.cached_balance }, -150 do
        create_expense(cc, 150)
      end
    end

    test "transfer moves the cached balance between sources" do
      from = create_source(name: "From #{Time.now.to_i}")
      to = create_source(name: "To #{Time.now.to_i}")

      assert_difference -> { from.reload.cached_balance }, -100 do
        assert_difference -> { to.reload.cached_balance }, 100 do
          Transfer.create!(user: @user, from_source: from, to_source: to, amount: 100, date: Date.today)
        end
      end
    end

    test "destroying a transfer reverses both sources" do
      from = create_source(name: "From #{Time.now.to_i}")
      to = create_source(name: "To #{Time.now.to_i}")
      transfer = Transfer.create!(user: @user, from_source: from, to_source: to, amount: 100, date: Date.today)

      assert_difference -> { from.reload.cached_balance }, 100 do
        assert_difference -> { to.reload.cached_balance }, -100 do
          transfer.destroy!
        end
      end
    end

    test "changing starting_balance adjusts the cached balance" do
      source = create_source

      assert_difference -> { source.reload.cached_balance }, 500 do
        source.update!(starting_balance: 1500)
      end
    end

    test "rebuild recalculates the cached balance from scratch" do
      source = create_source(starting_balance: 100)
      create_expense(source, 30)
      create_income(source, 200)

      source.update_column(:cached_balance, 999_999)

      MoneySources::BalanceSync.rebuild!(source)

      assert_equal BigDecimal("270"), source.reload.cached_balance
    end
  end
end
