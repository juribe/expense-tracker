# frozen_string_literal: true

require "test_helper"

class GmailSyncDispatchJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Dispatch User", email: "gmail_dispatch_test@example.com",
                         password: "password123")
    @active = GmailConnection.create!(user: @user, email: "active@gmail.com")
    @second = GmailConnection.create!(user: @user, email: "second@gmail.com")
    @inactive = GmailConnection.create!(user: @user, email: "inactive@gmail.com", active: false)
  end

  test "enqueues one sync job per active connection" do
    with_active_job_adapter(:test) do
      assert_enqueued_jobs 2, only: GmailSyncJob do
        assert_enqueued_with(job: GmailSyncJob, args: [ { connection_id: @active.id } ]) do
          assert_enqueued_with(job: GmailSyncJob, args: [ { connection_id: @second.id } ]) do
            GmailSyncDispatchJob.perform_now
          end
        end
      end
    end
  end

  test "does not enqueue inactive connections" do
    GmailConnection.update_all(active: false)

    with_active_job_adapter(:test) do
      assert_no_enqueued_jobs only: GmailSyncJob do
        GmailSyncDispatchJob.perform_now
      end
    end
  end
end
