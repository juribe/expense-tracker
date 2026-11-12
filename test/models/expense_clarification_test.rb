# frozen_string_literal: true

require "test_helper"

class ExpenseClarificationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Clarification Encryption",
      email: "clarification_encryption_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  test "normalizes the phone number to E.164" do
    clarification = @user.expense_clarifications.create!(
      phone_number: "57 300 111 2233",
      question: "¿Con qué fuente?",
      questions_count: 1
    )

    assert_equal "+573001112233", clarification.phone_number
  end

  test "stores the phone number encrypted at rest" do
    clarification = @user.expense_clarifications.create!(
      phone_number: "+57 300 111 2233",
      question: "¿Con qué fuente?",
      questions_count: 1
    )

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT phone_number FROM expense_clarifications WHERE id = #{ActiveRecord::Base.connection.quote(clarification.id)}"
    )

    assert_not_equal "+573001112233", raw
    assert_not_includes raw, "573001112233"
    assert_equal "+573001112233", clarification.reload.phone_number
  end
end
