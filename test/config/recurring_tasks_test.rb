# frozen_string_literal: true

require "test_helper"

class RecurringTasksTest < ActiveSupport::TestCase
  test "inbound email content is purged on a schedule" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)

    assert_equal "MailInboundContentPurgeJob",
                 config.dig("production", "mail_inbound_content_purge", "class")
  end

  test "old whatsapp message claims are purged on a schedule" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)

    assert_equal "WhatsappInboundMessagePurgeJob",
                 config.dig("production", "whatsapp_inbound_message_purge", "class")
  end
end
