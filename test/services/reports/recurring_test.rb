# frozen_string_literal: true

require "test_helper"

class ReportsRecurringTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Recurring User", email: "reports_recurring_test@example.com", password: "password123")
    @food = Category.create!(name: "Alimentación", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Davibank", kind: "account", active: true)
    @other = User.create!(name: "Other", email: "reports_recurring_other@example.com", password: "password123")
    @period = Reports::Period.new(preset: "this_month", date: Date.new(2026, 9, 15))
    @filter = Reports::Filter.new(user: @user, period: @period)
  end

  def template(name:, amount:, kind: "expense", frequency: "monthly", payment_day: 1, active: true, user: @user)
    RecurringTemplate.create!(user: user, category: @food, kind: kind, amount: amount,
                              frequency: frequency, payment_day: payment_day, active: active,
                              description: name)
  end

  def report
    Reports::Recurring.new(user: @user, filter: @filter).call
  end

  test "lists expense templates with amount, frequency, category and status" do
    template(name: "Internet", amount: 120_000, payment_day: 20)
    template(name: "Rent", amount: 2_500_000, payment_day: 5, active: false)

    data = report
    internet = data[:items].find { |i| i[:description] == "Internet" }

    assert_equal 2, data[:items].size
    assert_equal 120_000.to_d, internet[:amount]
    assert_equal "monthly", internet[:frequency]
    assert_equal "Alimentación", internet[:category_name]
    assert internet[:active]
    refute data[:items].find { |i| i[:description] == "Rent" }[:active]
  end

  test "normalizes frequencies to monthly and annual equivalents" do
    template(name: "Weekly gym", amount: 100_000, frequency: "weekly")
    template(name: "Monthly internet", amount: 120_000, frequency: "monthly")
    template(name: "Quarterly tax", amount: 300_000, frequency: "quarterly")
    template(name: "Annual insurance", amount: 1_200_000, frequency: "annual")
    template(name: "Mystery", amount: 50_000, frequency: "semestral")

    data = report
    by_name = data[:items].index_by { |i| i[:description] }

    assert_in_delta 433_333.33, by_name["Weekly gym"][:monthly_equivalent].to_f, 0.01
    assert_equal 120_000.to_d, by_name["Monthly internet"][:monthly_equivalent]
    assert_in_delta 100_000.0, by_name["Quarterly tax"][:monthly_equivalent].to_f, 0.01
    assert_equal 100_000.to_d, by_name["Annual insurance"][:monthly_equivalent]
    assert_equal 50_000.to_d, by_name["Mystery"][:monthly_equivalent], "unknown frequency falls back to monthly"
    assert_equal 1_440_000.to_d, by_name["Monthly internet"][:annual_equivalent]
  end

  test "computes monthly and annual committed amounts" do
    template(name: "Internet", amount: 120_000)
    template(name: "Rent", amount: 2_500_000)
    template(name: "Inactive", amount: 900_000, active: false)

    data = report

    assert_equal 2_620_000.to_d, data[:monthly_committed]
    assert_equal 31_440_000.to_d, data[:annual_committed]
  end

  test "income templates are counted separately" do
    template(name: "Salary", amount: 8_000_000, kind: "income")

    data = report

    assert_equal 8_000_000.to_d, data[:monthly_committed]
    assert_equal :income, data[:items].first[:kind]
  end

  test "upcoming payments for the next 7 days from today" do
    template(name: "Internet", amount: 120_000, payment_day: 20)
    template(name: "Rent", amount: 2_500_000, payment_day: 3)
    template(name: "Far away", amount: 99, payment_day: 28)

    travel_to Date.new(2026, 9, 15) do
      data = report
      upcoming = data[:upcoming]

      assert_equal %w[Internet], upcoming.map { |i| i[:description] }
      assert_equal 120_000.to_d, upcoming.first[:amount]
      assert_equal Date.new(2026, 9, 20), upcoming.first[:next_due_date]
    end
  end

  test "next due date handles day beyond month length" do
    template(name: "Car payment", amount: 2_818_000, payment_day: 31)

    travel_to Date.new(2026, 9, 25) do
      upcoming = report[:upcoming]

      assert_equal Date.new(2026, 9, 30), upcoming.first[:next_due_date], "clamps to September's last day"
    end
  end

  test "inactive templates are not upcoming" do
    template(name: "Old rent", amount: 1_000, payment_day: 20, active: false)

    travel_to Date.new(2026, 9, 15) do
      assert_empty report[:upcoming]
    end
  end

  test "only the user's templates are included" do
    template(name: "Mine", amount: 120_000)
    template(name: "Theirs", amount: 500_000, user: @other)

    assert_equal 1, report[:items].size
  end

  test "empty case yields zeroed structure" do
    data = report

    assert_empty data[:items]
    assert_equal 0.to_d, data[:monthly_committed]
    assert_equal 0.to_d, data[:annual_committed]
    assert_empty data[:upcoming]
  end
end
