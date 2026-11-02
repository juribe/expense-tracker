# frozen_string_literal: true

require "test_helper"

class GmailSyncJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Job User", email: "gmail_job_test@example.com", password: "password123")
    @connection = GmailConnection.create!(user: @user, email: "active@gmail.com",
                                          search_config: { senders: [ "notifications@bank.com" ] })
  end

  test "syncs exactly the connection passed by id" do
    synced = []

    stub_method(Gmail::SyncService, :call, ->(connection) { synced << connection.id; {} }) do
      GmailSyncJob.perform_now(connection_id: @connection.id)
    end

    assert_equal [ @connection.id ], synced
  end

  test "does not sync a connection another run has claimed" do
    @connection.update!(syncing: Time.current)
    calls = 0

    stub_method(Gmail::SyncService, :call, ->(*) { calls += 1; {} }) do
      GmailSyncJob.perform_now(connection_id: @connection.id)
    end

    assert_equal 0, calls
  end

  test "does not search a mailbox without saved criteria" do
    connection = GmailConnection.create!(user: @user, email: "unconfigured@gmail.com")
    calls = 0

    stub_method(Gmail::SyncService, :call, ->(*) { calls += 1; {} }) do
      GmailSyncJob.perform_now(connection_id: connection.id)
    end

    assert_equal 0, calls
    assert_nil connection.reload.syncing
  end

  test "claims syncing while the sync runs and stores the summary when complete" do
    summary = { fetched: 1, created: 1, failed: 0 }
    connection = @connection
    syncing_while_running = nil

    stub_method(Gmail::SyncService, :call, ->(*) do
      syncing_while_running = connection.reload.syncing
      summary
    end) do
      GmailSyncJob.perform_now(connection_id: connection.id)
    end

    assert_kind_of ActiveSupport::TimeWithZone, syncing_while_running
    @connection.reload
    assert_nil @connection.syncing
    assert_equal "1", @connection.last_sync_summary.fetch("fetched").to_s
    assert_equal "1", @connection.last_sync_summary.fetch("created").to_s
  end

  test "releases the claim and records an error summary when the sync fails" do
    silence_logger do
      stub_method(Gmail::SyncService, :call, ->(*) { raise StandardError, "network down" }) do
        GmailSyncJob.perform_now(connection_id: @connection.id)
      end
    end

    @connection.reload
    assert_nil @connection.syncing
    assert @connection.last_sync_summary["error"].present?
  end

  test "ignores a missing connection" do
    assert_nothing_raised do
      GmailSyncJob.perform_now(connection_id: -1)
    end
  end

  test "polling interval is configurable through the environment" do
    with_env({ "GMAIL_SYNC_INTERVAL_MINUTES" => nil }) do
      assert_operator GmailSyncJob.polling_interval_minutes, :>=, 1
    end
    with_env({ "GMAIL_SYNC_INTERVAL_MINUTES" => "45" }) do
      assert_equal 45, GmailSyncJob.polling_interval_minutes
    end
    with_env({ "GMAIL_SYNC_INTERVAL_MINUTES" => "9999" }) do
      assert_equal 1440, GmailSyncJob.polling_interval_minutes
    end
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
