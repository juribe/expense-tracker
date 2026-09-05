# frozen_string_literal: true

require "test_helper"

class GmailSetupSyncJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Setup Job User", email: "gmail_setup_job_test@example.com", password: "password123")
    @connection = GmailConnection.create!(user: @user, email: "active@gmail.com")
  end

  test "tracks syncing state and stores the summary when complete" do
    summary = { scanned: 10, passed: 2, suggestions: 3, senders: [], domains: [], subject_keywords: [] }
    stub_method(Gmail::SetupScanService, :call, summary) do
      GmailSetupSyncJob.perform_now(connection_id: @connection.id)
    end

    @connection.reload
    assert_nil @connection.syncing
    assert_equal 10, @connection.last_sync_summary["scanned"]
  end

  test "clears syncing and records an error summary when the scan fails" do
    silence_logger do
      stub_method(Gmail::SetupScanService, :call, ->(*) { raise StandardError, "network down" }) do
        GmailSetupSyncJob.perform_now(connection_id: @connection.id)
      end
    end

    @connection.reload
    assert_nil @connection.syncing
    assert @connection.last_sync_summary["error"].present?
  end

  test "ignores missing connections" do
    silence_logger do
      stub_method(Gmail::SetupScanService, :call, {}) do
        GmailSetupSyncJob.perform_now(connection_id: -1)
      end
    end

    assert_nil @connection.reload.syncing
  end

  test "skips a connection whose sync is already running" do
    @connection.update!(syncing: Time.current)
    calls = 0

    silence_logger do
      stub_method(Gmail::SetupScanService, :call, ->(*) { calls += 1; {} }) do
        GmailSetupSyncJob.perform_now(connection_id: @connection.id)
      end
    end

    assert_equal 0, calls
    assert_nil @connection.reload.last_sync_summary
  end

  test "runs when the syncing flag is stale (crashed previous run)" do
    @connection.update!(syncing: GmailConnection::STALE_SYNC_TIMEOUT.ago - 1.minute)
    calls = 0

    silence_logger do
      stub_method(Gmail::SetupScanService, :call, ->(*) { calls += 1; {} }) do
        GmailSetupSyncJob.perform_now(connection_id: @connection.id)
      end
    end

    assert_equal 1, calls
    assert_nil @connection.reload.syncing
  end

  private

  def silence_logger
    original = Rails.logger.level
    Rails.logger.level = Logger::ERROR
    yield
  ensure
    Rails.logger.level = original
  end
end
