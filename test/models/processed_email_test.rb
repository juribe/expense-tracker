# frozen_string_literal: true

require "test_helper"

class ProcessedEmailTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Processed Email User", email: "processed_email_test@example.com", password: "password123")
    @category = Category.create!(name: "Food PE", is_default: true, category_type: "expense")
    @email = ProcessedEmail.new(
      user: @user,
      provider: "gmail",
      message_id: "msg-1",
      status: "processed"
    )
  end

  test "is valid with provider, message id and status" do
    assert @email.valid?
  end

  test "requires message id" do
    @email.message_id = ""
    assert_not @email.valid?
  end

  test "enforces unique provider + message_id at the database level" do
    @email.save!
    duplicate = ProcessedEmail.new(user: @user, provider: "gmail", message_id: "msg-1", status: "processed")
    assert_raises(ActiveRecord::RecordNotUnique) do
      duplicate.save!(validate: false)
    end
  end

  test "payload_data parses stored json" do
    @email.payload = '{"transactions":[{"amount":100}]}'
    assert_equal({ "transactions" => [ { "amount" => 100 } ] }, @email.payload_data)
  end

  test "scopes filter by status" do
    @email.status = "needs_review"
    @email.save!
    assert_includes ProcessedEmail.gmail.needs_review, @email
    assert_not_includes ProcessedEmail.failed, @email
  end
end
