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

  test "sync_running? is true only for a recent syncing stamp" do
    @connection.syncing = nil
    assert_not @connection.sync_running?

    @connection.syncing = Time.current
    assert @connection.sync_running?

    @connection.syncing = GmailConnection::STALE_SYNC_TIMEOUT.ago - 1.minute
    assert_not @connection.sync_running?
  end

  test "authorization_expired? is true when the last sync failed with invalid_grant" do
    @connection.last_sync_summary = { "error" => "Google OAuth request failed (HTTP 400): { \"error\": \"invalid_grant\" }" }
    assert @connection.authorization_expired?
  end

  test "authorization_expired? is false for a healthy summary" do
    @connection.last_sync_summary = { "fetched" => 3, "created" => 1 }
    assert_not @connection.authorization_expired?
  end

  test "authorization_expired? is false for other sync errors" do
    @connection.last_sync_summary = { "error" => "Connection reset by peer" }
    assert_not @connection.authorization_expired?
  end

  test "authorization_expired? is false without a summary" do
    @connection.last_sync_summary = nil
    assert_not @connection.authorization_expired?
  end

  # --- criteria form values ---------------------------------------------------

  test "criteria_form_values returns the saved search config" do
    @connection.save!
    @connection.update!(search_config: { senders: [ "manual@bank.com" ],
                                         domains: [ "bank.com" ], subject_keywords: [ "pago" ] })

    assert_equal({ senders: "manual@bank.com", domains: "bank.com",
                   subject_keywords: "pago" }, @connection.criteria_form_values)
  end

  test "criteria_form_values merges scan suggestions into the saved config without duplicates" do
    @connection.save!
    @connection.update!(search_config: { senders: [ "manual@bank.com" ], domains: [],
                                         subject_keywords: [ "pago" ] })
    @connection.setup_suggestions = {
      "senders" => [ { "value" => "manual@bank.com", "count" => 2 },
                     { "value" => "notificaciones@davibank.com", "count" => 2 } ],
      "domains" => [ { "value" => "davibank.com", "count" => 2 } ],
      "subject_keywords" => [ { "value" => "transacción", "count" => 1 } ],
      "subject_templates" => [ { "value" => "Transacción aprobada por", "count" => 2,
                                 "institution" => "DAVIbank" } ]
    }

    values = @connection.criteria_form_values

    # The saved value keeps its original casing and leads the list.
    assert_equal "manual@bank.com, notificaciones@davibank.com", values[:senders]
    assert_equal "davibank.com", values[:domains]
    # Templates join the subject field: they search by subject too.
    assert_equal "pago, transacción, Transacción aprobada por", values[:subject_keywords]
  end

  test "criteria_form_values tolerates scalar or missing suggestion entries" do
    @connection.save!
    @connection.update!(search_config: {})
    @connection.setup_suggestions = {
      "senders" => [ "plain@bank.com" ],
      "subject_templates" => [ { "value" => "Compraste por" } ]
    }

    values = @connection.criteria_form_values

    assert_equal "plain@bank.com", values[:senders]
    assert_equal "Compraste por", values[:subject_keywords]
    assert_empty values[:domains]
  end
end
