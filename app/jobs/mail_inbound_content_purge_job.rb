# frozen_string_literal: true

# Scheduled cleanup for inbound email content that outlived its lifecycle.
class MailInboundContentPurgeJob < ApplicationJob
  queue_as :default

  def perform
    MailInbound::ContentPurger.new.run
  end
end
