# frozen_string_literal: true

require "test_helper"

class WhatsappInboundMessagePurgeJobTest < ActiveJob::TestCase
  test "removes old claims and keeps recent ones" do
    old = WhatsappInboundMessage.create!(mid: "old-mid", processed_at: 40.days.ago)
    recent = WhatsappInboundMessage.create!(mid: "recent-mid", processed_at: 1.day.ago)

    WhatsappInboundMessagePurgeJob.perform_now

    refute WhatsappInboundMessage.exists?(old.id)
    assert WhatsappInboundMessage.exists?(recent.id)
  end
end
