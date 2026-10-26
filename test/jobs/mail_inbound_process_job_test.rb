# frozen_string_literal: true

require "test_helper"

class MailInboundProcessJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(name: "Mail Process Job", email: "mail_process_job@example.com", password: "password123")
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
  end

  test "keeps the legacy job name as a compatibility shim" do
    assert_operator InboundEmailProcessJob, :<, MailInboundProcessJob
  end
end
