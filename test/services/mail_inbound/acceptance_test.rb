# frozen_string_literal: true

require "test_helper"

module MailInbound
  class AcceptanceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Inbound User", email: "mail_inbound_acceptance@example.com",
                           password: "password123")
      @other_user = User.create!(name: "Inbound Other", email: "mail_inbound_acceptance_other@example.com",
                                 password: "password123")
    end

    def message_for(user)
      Message.new(
        provider: "cloudflare",
        external_id: "ext-1",
        from: "notificaciones@bank.com",
        to: "inbox@example.com",
        subject: "Compra",
        body_text: "Compra aprobada",
        html: nil,
        headers: {},
        attachments: [],
        internal_date: Time.current,
        recipient: nil,
        user: user
      )
    end

    def accept(message)
      with_active_job_adapter(:test) do
        Acceptance.new(delivery: nil, message: message).call
      end
    end

    test "accepts the same provider message id for different users" do
      first, first_created = accept(message_for(@user))
      second, second_created = accept(message_for(@other_user))

      assert first_created
      assert second_created
      assert_equal @user, first.user
      assert_equal @other_user, second.user
      assert_equal 2, ProcessedEmail.where(provider: "cloudflare", message_id: "ext-1").count
    end

    test "is idempotent for the same user" do
      first, = accept(message_for(@user))
      second, created = accept(message_for(@user))

      refute created
      assert_equal first.id, second.id
      assert_equal 1, ProcessedEmail.where(provider: "cloudflare", message_id: "ext-1").count
    end
  end
end
