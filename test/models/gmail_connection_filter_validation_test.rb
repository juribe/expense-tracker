# frozen_string_literal: true

require "test_helper"

class GmailConnectionFilterValidationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Gmail Filters", email: "gmail_filters_#{SecureRandom.hex(4)}@example.com",
                         password: "password123")
  end

  test "empty search criteria do not configure the connection" do
    connection = GmailConnection.create!(
      user: @user,
      email: "empty-filters@example.com",
      search_config: { senders: [], domains: [], subject_keywords: [] }
    )

    refute connection.search_configured?
  end

  test "a real search criterion configures the connection" do
    connection = GmailConnection.create!(
      user: @user,
      email: "bank-filters@example.com",
      search_config: { senders: [ "notifications@bank.com" ], domains: [], subject_keywords: [] }
    )

    assert connection.search_configured?
  end
end
