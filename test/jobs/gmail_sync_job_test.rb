# frozen_string_literal: true

require "test_helper"

class GmailSyncJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Job User", email: "gmail_job_test@example.com", password: "password123")
    @active = GmailConnection.create!(user: @user, email: "active@gmail.com")
    @inactive = GmailConnection.create!(user: @user, email: "inactive@gmail.com", active: false)
  end

  test "syncs only active connections" do
    synced = []
    stub_method(GmailSyncJob, :polling_interval_minutes, 15) do
      stub_method(Gmail::SyncService, :call, ->(connection) { synced << connection.id; {} }) do
        GmailSyncJob.perform_now
      end
    end

    assert_includes synced, @active.id
    assert_not_includes synced, @inactive.id
  end

  test "a failing connection does not abort the run" do
    calls = 0
    service_stub = lambda do |connection|
      calls += 1
      raise StandardError, "network down" if connection.id == @active.id

      {}
    end

    silence_logger do
      stub_method(Gmail::SyncService, :call, service_stub) do
        GmailSyncJob.perform_now
      end
    end

    assert_equal 1, calls
  end

  test "can sync a single connection by id" do
    synced = []
    stub_method(Gmail::SyncService, :call, ->(connection) { synced << connection.id; {} }) do
      GmailSyncJob.perform_now(connection_id: @inactive.id)
    end

    assert_equal [ @inactive.id ], synced
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
