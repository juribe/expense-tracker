# frozen_string_literal: true

require "test_helper"

class GmailFilterWizardMoneyTrackingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = simple_user
    sign_in @user
  end

  test "simple mode shows editable Gmail criteria before the first scan" do
    connection = GmailConnection.create!(user: @user, email: "before-scan@example.com")

    get gmail_connection_path

    assert_response :success
    assert_select "textarea[name='search_config[senders]']"
    assert_select "textarea[name='search_config[domains]']"
    assert_select "textarea[name='search_config[subject_keywords]']"
    assert_select "[data-testid=bank-setup-wizard][data-auto-open=false]"
    assert_select "[data-testid=open-gmail-filter-wizard-header]"
    assert_equal connection, @user.gmail_connections.last
  end

  test "simple mode can open the bank email wizard while the connection is paused" do
    connection = GmailConnection.create!(user: @user, email: "paused@example.com", active: false)

    get gmail_connection_path(filters: "1")

    assert_response :success
    assert_select "[data-testid=open-gmail-filter-wizard-header]"
    assert_select "[data-testid=bank-setup-wizard][data-auto-open=true]"
    assert_select "[data-testid=bank-wizard-bank-step]"

    patch update_gmail_filters_path,
          params: { senders: [ "notifications@bank.com" ], subjects: [ "compra" ] },
          as: :json

    assert_response :success
    assert connection.reload.search_configured?
    refute connection.active?
  end

  test "simple setup sync stays on Gmail and opens the filter wizard" do
    GmailConnection.create!(user: @user, email: "setup-simple@example.com",
                            setup_suggestions: {
                              "senders" => [ { "value" => "notifications@bank.com", "count" => 2 } ],
                              "subject_keywords" => [ { "value" => "compra", "count" => 2 } ]
                            })

    get gmail_connection_path(filters: "1")

    assert_response :success
    assert_select "[data-testid=bank-setup-wizard][data-auto-open=true]"
    assert_select "[data-testid=bank-wizard-bank-step]", text: /Correos de bancos/
    assert_select "[data-testid=bank-wizard-filter-nav]", count: 0
    assert_select "[data-testid=bank-wizard-filter-step]", count: 0
    assert_select "body", text: /notifications@bank\.com/
  end

  test "simple setup sync redirects back to Gmail with the wizard flag" do
    GmailConnection.create!(user: @user, email: "setup-redirect@example.com")

    with_active_job_adapter(:test) do
      assert_enqueued_with(job: GmailSetupSyncJob) do
        post setup_sync_gmail_connection_path
      end
    end

    assert_redirected_to gmail_connection_path(filters: "1")
  end

  test "saving the simple wizard updates the Gmail search filters" do
    connection = GmailConnection.create!(user: @user, email: "save-filters@example.com")

    patch update_gmail_filters_path,
          params: { senders: [ "notifications@bank.com", "bank.com" ], subjects: [ "compra", "pago" ] },
          as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert body["configured"]
    connection.reload
    assert_equal [ "notifications@bank.com" ], connection.search_config_hash[:senders]
    assert_equal [ "bank.com" ], connection.search_config_hash[:domains]
    assert_equal [ "compra", "pago" ], connection.search_config_hash[:subject_keywords]
    assert connection.search_configured?
  end

  test "empty simple filters do not configure the connection" do
    connection = GmailConnection.create!(user: @user, email: "empty-filters@example.com")

    patch update_gmail_filters_path,
          params: { senders: [ "" ], subjects: [ "" ] },
          as: :json

    assert_response :unprocessable_entity
    refute connection.reload.search_configured?
    assert_includes JSON.parse(response.body)["errors"].join(" "), "remitente"
  end

  test "advanced setup sync keeps the recognition destination" do
    sign_out :user
    advanced = detailed_user
    sign_in advanced
    GmailConnection.create!(user: advanced, email: "advanced-gmail@example.com")

    with_active_job_adapter(:test) do
      post setup_sync_gmail_connection_path
    end

    assert_redirected_to money_sources_recognition_path
  end

  private

  def simple_user
    User.create!(name: "Gmail Simple", email: "gmail_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end

  def detailed_user
    User.create!(name: "Gmail Advanced", email: "gmail_advanced_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
