# frozen_string_literal: true

require "test_helper"

class GmailConnectionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Gmail User", email: "gmail_connection_test@example.com", password: "password123")
    @connection = GmailConnection.new(
      user: @user,
      email: "me@gmail.com",
      access_token: "plain-access-token",
      refresh_token: "plain-refresh-token",
      token_expires_at: 1.hour.from_now
    )
  end

  test "is valid with user and email" do
    assert @connection.valid?
  end

  test "requires email" do
    @connection.email = ""
    assert_not @connection.valid?
  end

  test "email is unique per user" do
    @connection.save!
    duplicate = GmailConnection.new(user: @user, email: "me@gmail.com")
    assert_not duplicate.valid?
  end

  test "stores oauth tokens encrypted at rest" do
    @connection.save!
    raw_access = @connection.read_attribute(:access_token)
    raw_refresh = @connection.read_attribute(:refresh_token)

    assert_not_equal "plain-access-token", raw_access
    assert_not_equal "plain-refresh-token", raw_refresh
    assert_equal "plain-access-token", @connection.access_token
    assert_equal "plain-refresh-token", @connection.refresh_token
  end

  test "token_expired? is true without expiry or when close to expiring" do
    @connection.token_expires_at = nil
    assert @connection.token_expired?

    @connection.token_expires_at = 10.seconds.from_now
    assert @connection.token_expired?

    @connection.token_expires_at = 10.minutes.from_now
    assert_not @connection.token_expired?
  end

  test "fresh_access_token! returns stored token while valid" do
    @connection.save!
    assert_equal "plain-access-token", @connection.fresh_access_token!
  end

  test "fresh_access_token! refreshes through Google when expired" do
    @connection.save!
    @connection.update!(token_expires_at: 1.minute.ago)

    stub_method(Gmail::OauthClient, :refresh, { access_token: "new-token", expires_at: 1.hour.from_now, refresh_token: nil }) do
      assert_equal "new-token", @connection.fresh_access_token!
    end

    assert_equal "new-token", @connection.reload.access_token
  end

  test "search_config_hash normalizes criteria" do
    @connection.search_config = { senders: [ " a@bank.com ", "" ], domains: [ "bank.com" ] }
    config = @connection.search_config_hash

    assert_equal [ "a@bank.com" ], config[:senders]
    assert_equal [ "bank.com" ], config[:domains]
    assert_equal [], config[:subject_keywords]
  end
end
