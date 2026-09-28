# frozen_string_literal: true

require "test_helper"

class RecurringTemplateProcessorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Rtp User", email: "rtp_test@example.com", password: "password123")
    @category = Category.create!(name: "RTP Cat", is_default: false, category_type: "expense", user: @user)
    @savings = @user.money_sources.create!(name: "Ahorros", kind: "account")
    @template = @user.recurring_templates.create!(
      category: @category, kind: "expense", amount: 30_000, frequency: "monthly",
      source: "wizard", description: "Seguro", money_source: @savings
    )
  end

  test "uses the template's money source by default" do
    result = RecurringTemplateProcessor.call(recurring_template: @template, amount: 30_000, date: Date.current)

    assert result.success?
    assert_equal @savings.id, result.transaction.money_source_id
  end

  test "uses the explicitly given money source over the template's" do
    wallet = @user.money_sources.create!(name: "Nequi", kind: "wallet")
    result = RecurringTemplateProcessor.call(
      recurring_template: @template, amount: 30_000, date: Date.current, money_source: wallet
    )

    assert result.success?
    assert_equal wallet.id, result.transaction.money_source_id
    assert_equal @template.id, result.transaction.recurring_template_id
  end

  test "still enforces one transaction per period even with a different source" do
    wallet = @user.money_sources.create!(name: "Nequi", kind: "wallet")
    RecurringTemplateProcessor.call(recurring_template: @template, amount: 30_000, date: Date.current)

    result = RecurringTemplateProcessor.call(
      recurring_template: @template, amount: 30_000, date: Date.current, money_source: wallet
    )

    assert_not result.success?
    assert_match(/Already processed/, result.error)
  end
end
