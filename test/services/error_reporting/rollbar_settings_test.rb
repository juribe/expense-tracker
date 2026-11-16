# frozen_string_literal: true

require "test_helper"

module ErrorReporting
  class RollbarSettingsTest < ActiveSupport::TestCase
    def settings(env: {}, rails_env: "production", filters: [])
      RollbarSettings.new(env: env, rails_env: rails_env, filter_parameters: filters)
    end

    test "enables reporting in production when a project token exists" do
      subject = settings(env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" })

      assert subject.enabled?
      assert_equal "server-token", subject.access_token
      assert_equal "production", subject.environment
    end

    test "enables reporting in staging when it is configured" do
      subject = settings(env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" }, rails_env: "staging")

      assert subject.enabled?
    end

    test "disables reporting in development and test by default" do
      %w[development test].each do |environment|
        subject = settings(env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" }, rails_env: environment)

        refute subject.enabled?, "expected Rollbar to be disabled in #{environment}"
      end
    end

    test "stays disabled when the project token is missing" do
      subject = settings(env: {})

      refute subject.enabled?
      assert_nil subject.access_token
      assert_equal "production", subject.environment
    end

    test "honors the temporary disable flag" do
      subject = settings(env: {
        "ROLLBAR_ACCESS_TOKEN" => "server-token",
        "ROLLBAR_ENABLED" => "false"
      })

      refute subject.enabled?
    end

    test "uses APP_VERSION as the code version" do
      subject = settings(env: {
        "ROLLBAR_ACCESS_TOKEN" => "server-token",
        "APP_VERSION" => "abc123def456"
      })

      assert_equal "abc123def456", subject.config_attributes[:code_version]
    end

    test "uses an internal user id and never exposes email or username" do
      attributes = settings(env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" }).config_attributes

      assert_equal "current_user", attributes[:person_method]
      assert_equal "id", attributes[:person_id_method]
      assert_nil attributes[:person_username_method]
      assert_nil attributes[:person_email_method]
    end

    test "merges Rails filter parameters into Rollbar scrub fields" do
      attributes = settings(
        env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" },
        filters: [ :email, :description, :bank_statement ]
      ).config_attributes

      assert_includes attributes[:scrub_fields], :email
      assert_includes attributes[:scrub_fields], :description
      assert_includes attributes[:scrub_fields], :bank_statement
      assert_includes attributes[:scrub_fields], :card_number
      assert_includes attributes[:scrub_fields], :whatsapp_access_token
    end

    test "does not collect user IP addresses or local variables" do
      attributes = settings(env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" }).config_attributes

      assert_equal false, attributes[:collect_user_ip]
      assert_equal :none, attributes[:send_extra_frame_data]
      assert_equal false, attributes[:log_payload]
    end

    test "ignores expected application exceptions" do
      levels = settings(env: {}).ignored_exception_levels

      assert_equal "ignore", levels["ActiveRecord::RecordNotFound"]
      assert_equal "ignore", levels["ActionController::RoutingError"]
      assert_equal "ignore", levels["ActionController::InvalidAuthenticityToken"]
      assert_equal "ignore", levels["ActionController::ParameterMissing"]
      assert_equal "ignore", levels["ActionDispatch::Http::Parameters::ParseError"]
    end

    test "enables the Rails error subscriber when reporting is enabled" do
      attributes = settings(env: { "ROLLBAR_ACCESS_TOKEN" => "server-token" }).config_attributes

      assert_equal true, attributes[:enable_rails_error_subscriber]
    end

    test "the test environment boots with Rollbar disabled" do
      refute Rollbar.configuration.enabled
      assert_equal "id", Rollbar.configuration.person_id_method
      assert_nil Rollbar.configuration.person_username_method
      assert_nil Rollbar.configuration.person_email_method
      assert_equal false, Rollbar.configuration.collect_user_ip
      assert_includes Rollbar.configuration.scrub_headers, "Cookie"
      assert_includes Rollbar.configuration.scrub_headers, "Authorization"
      assert Rollbar.configuration.transform.any?
    end
  end
end
