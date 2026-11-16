# frozen_string_literal: true

require "test_helper"

class RollbarErrorReportingTest < ActiveSupport::TestCase
  def capture_rollbar_log
    calls = []
    stub_method(Rollbar, :log, ->(*args) { calls << args; "ok" }) do
      yield calls
    end
    calls
  end

  test "reports unhandled exceptions at error severity" do
    error = StandardError.new("unexpected boom")

    calls = capture_rollbar_log do
      Rollbar::ErrorSubscriber.new.report(
        error,
        handled: false,
        severity: :error,
        context: {},
        source: "application.action_dispatch"
      )
    end

    assert_equal 1, calls.length
    level, reported_error, extra = calls.first
    assert_equal :error, level
    assert_same error, reported_error
    assert_equal true, extra[:is_uncaught]
    assert_equal true, extra[:use_exception_level_filters]
    assert_equal "application.action_dispatch", extra[:custom_data_method_context]
  end

  test "preserves the severity of handled failures" do
    error = Net::OpenTimeout.new("provider timed out")

    calls = capture_rollbar_log do
      Rollbar::ErrorSubscriber.new.report(
        error,
        handled: true,
        severity: :warning,
        context: {},
        source: "application.solid_queue"
      )
    end

    level, _reported_error, extra = calls.first
    assert_equal :warning, level
    assert_equal false, extra[:is_uncaught]
    assert_equal false, extra[:use_exception_level_filters]
  end

  test "reduces background job context to the job class" do
    job = GmailSyncJob.new(connection_id: "connection-1")

    calls = capture_rollbar_log do
      Rollbar::ErrorSubscriber.new.report(
        StandardError.new("job failed"),
        handled: false,
        severity: :error,
        context: { job: job },
        source: "application.solid_queue"
      )
    end

    _level, _error, extra = calls.first
    assert_equal "GmailSyncJob", extra[:job]
    refute extra.key?(:arguments)
    refute_includes JSON.generate(extra), "connection-1"
  end

  test "handles anonymous requests safely" do
    controller_class = Class.new do
      include Rollbar::Rails::ControllerMethods

      def current_user
        nil
      end
    end

    assert_equal({}, controller_class.new.rollbar_person_data)
  end

  test "uses the internal user id and no personal identifiers" do
    user = Struct.new(:id, :email, :username).new("user-uuid", "user@example.com", "financial-user")
    controller_class = Class.new do
      include Rollbar::Rails::ControllerMethods

      define_method(:initialize) { |current_user| @current_user = current_user }
      define_method(:current_user) { @current_user }
    end

    person = controller_class.new(user).rollbar_person_data

    assert_equal "user-uuid", person[:id]
    assert_nil person[:email]
    assert_nil person[:username]
  end

  test "a Rollbar failure does not break the reporting caller" do
    subscriber = Rollbar::ErrorSubscriber.new
    original_logger = Rails.error.logger
    Rails.error.logger = Logger.new(IO::NULL)

    stub_method(Rollbar, :log, ->(*) { raise "rollbar unavailable" }) do
      Rails.error.subscribe(subscriber)

      assert_nothing_raised do
        Rails.error.report(StandardError.new("application error"), handled: false)
      end
    end
  ensure
    Rails.error.unsubscribe(Rollbar::ErrorSubscriber)
    Rails.error.logger = original_logger
  end
end
