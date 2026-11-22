# frozen_string_literal: true

require "test_helper"

module Expenses
  class MoneyTrackingPipelineTest < ActiveSupport::TestCase
    setup do
      @category = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
      @saved_api_key = ENV.delete("MISTRAL_API_KEY")
    end

    teardown do
      ENV["MISTRAL_API_KEY"] = @saved_api_key
    end

    test "WhatsApp pipeline in simple mode completes the candidate with General" do
      user = simple_user
      general = user.general_money_source

      result = Processor.call(
        user: user,
        input: Input.from_params("text", text: "Me gasté 30 mil en almuerzos con mi Visa"),
        source: "whatsapp"
      )

      candidate = result.candidates.first
      assert result.ok?, [ result.errors, candidate&.errors&.full_messages, candidate&.attributes ].inspect
      assert_equal general.id, candidate.money_source_id
      assert candidate.ready?
      refute_includes candidate.missing_fields, "money_source_id"

      candidate.confirm!
      assert_equal general.id, candidate.expense.reload.money_source_id
    end

    test "AI-persisted candidates in simple mode complete the source with General" do
      user = simple_user
      general = user.general_money_source

      candidate = ExpenseCandidate.create!(
        user: user,
        amount: 12_000,
        date: Date.current,
        description: "Almuerzo IA",
        category: @category,
        source: "ai"
      )

      assert_equal general.id, candidate.money_source_id
      assert_equal "ready", candidate.status
      refute_includes candidate.missing_fields, "money_source_id"
    end

    test "WhatsApp pipeline in advanced mode keeps the detected source" do
      user = detailed_user
      visa = user.money_sources.create!(name: "Visa", kind: "credit_card", identifier: "1234")
      user.update!(default_money_source: user.money_sources.create!(name: "Cuenta", kind: "account"))

      result = Processor.call(
        user: user,
        input: Input.from_params("text", text: "Me gasté 30 mil en almuerzos con mi Visa"),
        source: "whatsapp"
      )

      candidate = result.candidates.first
      assert_equal visa.id, candidate.money_source_id
      assert candidate.ready?
    end

    test "advanced candidates without a source still need review" do
      user = detailed_user

      candidate = ExpenseCandidate.create!(
        user: user,
        amount: 12_000,
        date: Date.current,
        description: "Almuerzo sin fuente",
        category: @category,
        source: "ai"
      )

      assert_nil candidate.money_source_id
      assert_includes candidate.missing_fields, "money_source_id"
      assert_equal "needs_review", candidate.status
    end

    private

    def simple_user
      user = User.create!(name: "Simple Pipeline", email: "simple_pipeline_#{SecureRandom.hex(4)}@example.com",
                          password: "password123")
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      user.ensure_general_money_source!
      user
    end

    def detailed_user
      User.create!(name: "Advanced Pipeline", email: "advanced_pipeline_#{SecureRandom.hex(4)}@example.com",
                   password: "password123")
    end
  end
end
