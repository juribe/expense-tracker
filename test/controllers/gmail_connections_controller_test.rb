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

  test "start_auth redirects to google when oauth is configured" do
    with_env({ "GOOGLE_CLIENT_ID" => "client-id", "GOOGLE_CLIENT_SECRET" => "client-secret" }) do
      post start_gmail_auth_path

      assert_response :redirect
      assert_match(%r{\Ahttps://accounts\.google\.com/o/oauth2/v2/auth}, @response.headers["Location"])
      assert_includes @response.headers["Location"], "client_id=client-id"
      refute_nil session[:gmail_oauth_state]
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

  test "sync reports a summary" do
    GmailConnection.create!(user: @user, email: "me@gmail.com")
    stub_method(Gmail::SyncService, :call, { fetched: 0, created: 0, ignored: 0, needs_review: 0, failed: 0, skipped: 0 }) do
      post sync_gmail_connection_path
    end

    assert_redirected_to gmail_connection_path
    assert_match(/Sincronización terminada/, flash[:notice])
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
