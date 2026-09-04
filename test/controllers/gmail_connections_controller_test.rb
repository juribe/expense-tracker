# frozen_string_literal: true

require "test_helper"

class GmailConnectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Gmail Ctl User", email: "gmail_ctl_test@example.com", password: "password123")
    sign_in @user
  end

  test "requires authentication" do
    sign_out :user

    get gmail_connection_path

    assert_redirected_to new_user_session_path
  end

  test "index renders the settings page" do
    get gmail_connection_path

    assert_response :success
    assert_select "h1", text: I18n.t("gmail.title")
  end

  test "index renders the sync button with a loading spinner for an active connection" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")

    get gmail_connection_path

    assert_response :success
    assert_select "button", text: /#{I18n.t("gmail.sync_now")}/
    assert_select "button[data-turbo-submits-with]"
  end

  test "start_auth redirects to google when oauth is configured" do
    source = @user.money_sources.create!(name: "Davibank", kind: "account", starting_balance: 0, bank: "davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])

    with_env({ "GOOGLE_CLIENT_ID" => "client-id", "GOOGLE_CLIENT_SECRET" => "client-secret" }) do
      post start_gmail_auth_path

      assert_response :redirect
      assert_match(%r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, @response.headers["Location"])
      assert_includes @response.headers["Location"], "client_id=client-id"
      refute_nil session[:gmail_oauth_state]
    end
  end

  test "start_auth blocks gmail when the user has no money sources" do
    with_env({ "GOOGLE_CLIENT_ID" => "client-id", "GOOGLE_CLIENT_SECRET" => "client-secret" }) do
      post start_gmail_auth_path

      assert_redirected_to money_sources_recognition_path
      assert_equal I18n.t("money_sources.recognition.gmail_blocked"), flash[:alert]
      assert_nil session[:gmail_oauth_state]
    end
  end

  test "start_auth allows gmail without recognition configuration (first sync discovers it)" do
    @user.money_sources.create!(name: "Davibank", kind: "account", starting_balance: 0, bank: "davibank")

    with_env({ "GOOGLE_CLIENT_ID" => "client-id", "GOOGLE_CLIENT_SECRET" => "client-secret" }) do
      post start_gmail_auth_path

      assert_response :redirect
      assert_match(%r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, @response.headers["Location"])
      assert_includes @response.headers["Location"], "client_id=client-id"
      refute_nil session[:gmail_oauth_state]
    end
  end

  test "start_auth allows gmail when a source is recognition-configured" do
    source = @user.money_sources.create!(name: "Davibank", kind: "account", starting_balance: 0, bank: "davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])

    with_env({ "GOOGLE_CLIENT_ID" => "client-id", "GOOGLE_CLIENT_SECRET" => "client-secret" }) do
      post start_gmail_auth_path

      assert_response :redirect
      assert_match(%r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, @response.headers["Location"])
    end
  end

  test "start_auth explains missing configuration instead of failing" do
    with_env({ "GOOGLE_CLIENT_ID" => nil, "GOOGLE_CLIENT_SECRET" => nil }) do
      post start_gmail_auth_path

      assert_redirected_to gmail_connection_path
      assert_match(/configurado/, flash[:alert])
    end
  end

  test "callback rejects mismatched oauth state (CSRF)" do
    get google_callback_path, params: { code: "abc", state: "evil-state" }

    assert_redirected_to gmail_connection_path
    assert_match(/estado/i, flash[:alert])
    assert_equal 0, GmailConnection.count
  end

  test "callback connects the gmail account and stores tokens" do
    source = @user.money_sources.create!(name: "Davibank", kind: "account", starting_balance: 0, bank: "davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])

    with_env({ "GOOGLE_CLIENT_ID" => "client-id", "GOOGLE_CLIENT_SECRET" => "client-secret" }) do
      post start_gmail_auth_path
      assert_response :redirect
      state = session[:gmail_oauth_state]

      exchange_result = { access_token: "at", refresh_token: "rt", expires_at: 1.hour.from_now, id_token: nil }
      stub_method(Gmail::OauthClient, :exchange_code, exchange_result) do
        stub_method(Gmail::OauthClient, :userinfo, { sub: "google-sub-123", email: "me@gmail.com" }) do
          get google_callback_path, params: { code: "abc", state: state }
        end
      end
    end

    assert_redirected_to gmail_connection_path
    assert_not_nil flash[:notice]

    connection = @user.gmail_connections.reload.last
    assert_equal "me@gmail.com", connection.email
    assert_equal "google-sub-123", connection.google_account_id
    assert_equal "at", connection.access_token
    assert_equal "rt", connection.refresh_token
    assert connection.active?
    assert_nil session[:gmail_oauth_state]
  end

  test "update saves search criteria under the search_config column" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")

    patch gmail_connection_path, params: {
      search_config: { senders: "notifications@bank.com, alerts@nequi.co", domains: "", subject_keywords: "" }
    }

    assert_redirected_to gmail_connection_path
    assert_equal I18n.t("gmail_messages.criteria_updated"), flash[:notice]

    connection = @user.gmail_connections.last
    assert_equal [ "notifications@bank.com", "alerts@nequi.co" ], connection.search_config_hash[:senders]
    assert_equal [], connection.search_config_hash[:domains]
    assert_equal [], connection.search_config_hash[:subject_keywords]
  end

  test "disconnect removes the connection but keeps processed email history" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")
    ProcessedEmail.create!(user: @user, provider: "gmail", message_id: "m1", status: "processed")

    delete gmail_connection_path

    assert_redirected_to gmail_connection_path
    assert_equal 0, GmailConnection.count
    assert_equal 1, ProcessedEmail.count
  end

  test "sync enqueues a background job instead of blocking the request" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")

    with_active_job_adapter(:test) do
      assert_enqueued_with(job: GmailSyncJob) do
        post sync_gmail_connection_path
      end
    end

    assert_redirected_to gmail_connection_path
    assert_match(/segundo plano/, flash[:notice])
  end

  test "sync_status reports a running sync" do
    connection = GmailConnection.create!(user: @user, email: "me@gmail.com")
    connection.update_column(:syncing, Time.current)

    get gmail_sync_status_path

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["syncing"]
    assert_nil body["summary"]
  end

  test "sync_status reports the stored summary once complete" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")
    GmailConnection.first.update!(syncing: nil, last_sync_summary: { fetched: 3, created: 2, failed: 1 })

    get gmail_sync_status_path

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal false, body["syncing"]
    assert_equal 3, body["summary"]["fetched"]
  end

  test "sync runs the job which reports the summary" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")
    connection = GmailConnection.first
    summary = { fetched: 0, created: 0, ignored: 0, needs_review: 0, failed: 0, skipped: 0 }
    calls = 0

    stub_method(Gmail::SyncService, :call, ->(*) { calls += 1; summary }) do
      with_active_job_adapter(:inline) do
        GmailSyncJob.perform_later(connection_id: connection.id)
      end
    end

    assert_equal 1, calls
  end

  test "approve creates expenses from a reviewed transaction" do
    category = Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
    review = ProcessedEmail.create!(
      user: @user,
      provider: "gmail",
      message_id: "msg-review-1",
      status: "needs_review",
      payload: {
        subject: "Compra",
        transactions: [
          {
            "type" => "expense", "amount" => 48_500, "currency" => "COP",
            "merchant" => "Restaurante XYZ", "category" => "restaurants",
            "occurred_at" => "2026-08-23T14:30:00", "confidence" => 0.4
          }
        ]
      }.to_json
    )

    post approve_gmail_review_path(review)

    assert_redirected_to gmail_connection_path
    review.reload
    assert_equal "processed", review.status

    expense = Expense.find(review.expense_id)
    assert_equal BigDecimal("-48500.0"), expense.amount
    assert_equal "gmail", expense.source
    assert_equal category.id, expense.category_id
    assert_equal "msg-review-1", expense.gmail_message_id
  end

  test "reject discards a reviewed transaction without creating expenses" do
    review = ProcessedEmail.create!(user: @user, provider: "gmail", message_id: "msg-review-2",
                                    status: "needs_review", payload: "{}")

    post reject_gmail_review_path(review)

    assert_redirected_to gmail_connection_path
    assert_equal "ignored", review.reload.status
    assert_equal 0, Expense.count
  end

  test "users cannot touch other users' reviews" do
    other_user = User.create!(name: "Other", email: "gmail_other@example.com", password: "password123")
    foreign = ProcessedEmail.create!(user: other_user, provider: "gmail", message_id: "foreign-msg",
                                     status: "needs_review", payload: "{}")

    post approve_gmail_review_path(foreign)
    assert_response :not_found
  end
end
