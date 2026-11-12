# frozen_string_literal: true

require "test_helper"

class MailInboundProcessJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Mail Process Job", email: "mail_process_job@example.com", password: "password123")
    @user.email_sources.create!(
      source_type: "forwarding",
      email: "notificaciones@bank.example",
      status: "active"
    )
    @record = ProcessedEmail.create!(
      user: @user,
      provider: "cloudflare",
      message_id: "process-job@example.com",
      status: "queued",
      payload: JSON.generate(
        "email" => {
          "id" => "process-job@example.com",
          "from" => "Banco <notificaciones@bank.example>",
          "to" => [ "receive+user1@samyreplies.com" ],
          "subject" => "Compra aprobada",
          "body_text" => "Compra por $48.500",
          "html" => nil,
          "internal_date" => "2026-08-23T14:30:00Z",
          "headers" => [],
          "attachments" => []
        }
      )
    )
  end

  class FakeProcessor
    attr_reader :calls

    def initialize(result: nil, error: nil)
      @result = result
      @error = error
      @calls = []
    end

    def call(message)
      @calls << message
      raise @error if @error

      @result
    end
  end

  def result
    Struct.new(:status, :reason).new(:processed, nil)
  end

  test "runs the processor with the stored provider and user" do
    processor = FakeProcessor.new(result: result)
    captured = nil

    stub_method(MailInbound::Processor, :new, lambda { |user:, provider:, source:|
      captured = { user: user, provider: provider, source: source }
      processor
    }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    assert_equal @user, captured[:user]
    assert_equal "cloudflare", captured[:provider]
    assert_equal 1, processor.calls.size
    assert_equal "Compra aprobada", processor.calls.first["subject"]
    assert_nil @record.reload.payload_data["email"]
  end

  test "marks a missing payload as failed" do
    @record.update!(payload: nil)

    assert_nothing_raised { MailInboundProcessJob.perform_now(@record.id) }

    @record.reload
    assert_equal "failed", @record.status
    assert_match(/payload/i, @record.failure_reason)
  end

  test "retries processor failures" do
    processor = FakeProcessor.new(error: StandardError.new("AI down"))

    with_active_job_adapter(:test) do
      stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
        assert_nothing_raised { MailInboundProcessJob.perform_now(@record.id) }
      end

      assert_enqueued_with(job: MailInboundProcessJob, args: [ @record.id ])
    end

    assert @record.reload.payload_data["email"].present?
  end

  test "purges stored content after the final retry" do
    processor = FakeProcessor.new(error: StandardError.new("AI down"))

    with_active_job_adapter(:test) do
      stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
        job = MailInboundProcessJob.new(@record.id)
        job.exception_executions = { "[StandardError]" => 4 }
        job.perform_now
      end
    end

    assert_nil @record.reload.payload_data["email"]
  end

  test "purges content after a terminal failed result without raising" do
    failed = Struct.new(:status).new(:failed)
    processor = FakeProcessor.new(result: failed)

    stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    assert_nil @record.reload.payload_data["email"]
  end

  test "keeps review data when purging a needs_review email" do
    @record.update!(
      payload: JSON.generate(
        "email" => { "subject" => "Compra aprobada", "body_text" => "Compra por $48.500" },
        "subject" => "Compra aprobada",
        "transactions" => [ { "amount" => 48_500 } ]
      )
    )
    review = Struct.new(:status).new(:needs_review)
    processor = FakeProcessor.new(result: review)

    stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    @record.reload
    assert_nil @record.payload_data["email"]
    assert_equal "Compra aprobada", @record.payload_data["subject"]
    assert_equal [ { "amount" => 48_500 } ], @record.payload_data["transactions"]
  end

  test "does not reprocess a terminal row whose content was already purged" do
    @record.update!(status: "processed", payload: nil)

    MailInboundProcessJob.perform_now(@record.id)

    @record.reload
    assert_equal "processed", @record.status
    assert_nil @record.failure_reason
  end

  test "purges leftover content when a terminal row is re-enqueued" do
    @record.update!(status: "processed")

    MailInboundProcessJob.perform_now(@record.id)

    @record.reload
    assert_equal "processed", @record.status
    assert_nil @record.payload_data["email"]
  end

  test "ignores inbound email when the user has no active premium membership" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    processor = FakeProcessor.new(result: result)

    stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    @record.reload
    assert_equal "ignored", @record.status
    assert_match(/premium/i, @record.failure_reason)
    assert_nil @record.payload_data["email"]
    assert_empty processor.calls
  end

  test "ignores inbound email when the premium membership is expired" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "active", expires_at: 1.day.ago)
    processor = FakeProcessor.new(result: result)

    stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    @record.reload
    assert_equal "ignored", @record.status
    assert_match(/premium/i, @record.failure_reason)
    assert_empty processor.calls
  end

  test "processes inbound email for a user with an active premium membership" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    create_membership(status: "active", expires_at: 1.month.from_now)
    processor = FakeProcessor.new(result: result)

    stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    assert_equal 1, processor.calls.size
  end

  test "processes inbound email when paid access is not required" do
    PaymentEngine::Setting.current.update!(paid_access_required: false)
    processor = FakeProcessor.new(result: result)

    stub_method(MailInbound::Processor, :new, ->(*, **) { processor }) do
      MailInboundProcessJob.perform_now(@record.id)
    end

    assert_equal 1, processor.calls.size
  end

  test "does not downgrade a terminal row when the user has no premium membership" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    @record.update!(status: "processed")

    MailInboundProcessJob.perform_now(@record.id)

    @record.reload
    assert_equal "processed", @record.status
    assert_nil @record.failure_reason
  end

  test "keeps the legacy job name as a compatibility shim" do
    assert_operator InboundEmailProcessJob, :<, MailInboundProcessJob
  end

  private

  def create_membership(status:, expires_at:)
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: membership_type,
      status: status,
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: expires_at
    )
  end

  def membership_type
    @membership_type ||= PaymentEngine::MembershipType.create!(
      name: "Mail Inbound Process Premium",
      code: "MAIL_INBOUND_PROCESS_#{SecureRandom.hex(6)}",
      status: "active"
    )
  end
end
