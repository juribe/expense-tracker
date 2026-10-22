# frozen_string_literal: true

require "test_helper"

class MonthlyReportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Monthly Reports User", email: "monthly_reports_test@example.com",
                         password: "password123")
    @account = MoneySource.create!(user: @user, name: "Davibank", kind: "account", starting_balance: 10_000_000)
    @category = Category.create!(user: @user, name: "Mercado")
  end

  test "show loads categories without an N+1 query" do
    categories = [ @category, Category.create!(user: @user, name: "Transporte"),
                   Category.create!(user: @user, name: "Ocio") ]
    categories.each_with_index do |category, index|
      @user.expenses.create!(
        category: category, description: "Compra #{index}", amount: 50_000,
        kind: "expense", source: "manual", date: Date.new(2026, 10, 10 + index),
        money_source: @account
      )
    end
    @user.incomes.create!(
      category: Category.create!(user: @user, name: "Salario"), description: "Salario",
      amount: 3_000_000, kind: "income", source: "manual", date: Date.new(2026, 10, 15),
      money_source: @account
    )
    sign_in @user

    category_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:cached]

      category_queries << payload[:sql] if payload[:sql].match?(/FROM "categories"/i)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get monthly_report_path("2026-10")
    end

    assert_response :success
    # One preload per relation (incomes + expenses), regardless of how many
    # transactions the month has.
    assert_equal 2, category_queries.size
  end
end
