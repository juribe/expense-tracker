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

  test "enqueues only connections whose owner has an active premium membership" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(@user, status: "active", expires_at: 1.month.from_now)

    expired_user = create_user("expired")
    GmailConnection.create!(user: expired_user, email: "expired@gmail.com")
    create_membership(expired_user, status: "expired", expires_at: 1.day.ago)

    free_user = create_user("free")
    GmailConnection.create!(user: free_user, email: "free@gmail.com")

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

  test "enqueues every active connection when paid access is not required" do
    PaymentEngine::Setting.current.update!(paid_access_required: false)

    with_active_job_adapter(:test) do
      assert_enqueued_jobs 2, only: GmailSyncJob do
        GmailSyncDispatchJob.perform_now
      end
    end
  end

  test "enqueues one job when the owner has multiple active memberships" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(@user, status: "active", expires_at: 1.month.from_now)
    create_membership(@user, status: "active", expires_at: 2.months.from_now)

    with_active_job_adapter(:test) do
      assert_enqueued_jobs 2, only: GmailSyncJob do
        GmailSyncDispatchJob.perform_now
      end
    end
  end

  test "does not add a query per connection" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(@user, status: "active", expires_at: 1.month.from_now)

    few_connections = count_sql_queries do
      with_active_job_adapter(:test) { GmailSyncDispatchJob.perform_now }
    end

    3.times { |index| GmailConnection.create!(user: @user, email: "extra#{index}@gmail.com") }

    many_connections = count_sql_queries do
      with_active_job_adapter(:test) { GmailSyncDispatchJob.perform_now }
    end

    assert_equal few_connections, many_connections
  end

  private

  def create_user(label)
    User.create!(
      name: "Dispatch #{label} User",
      email: "gmail_dispatch_#{label}_#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  def create_membership(user, status:, expires_at:)
    PaymentEngine::Membership.create!(
      owner: user,
      membership_type: membership_type,
      status: status,
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end

  def membership_type
    @membership_type ||= PaymentEngine::MembershipType.create!(
      name: "Gmail Dispatch Premium",
      code: "GMAIL_DISPATCH_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end

  def count_sql_queries
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"

      count += 1
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end
end
