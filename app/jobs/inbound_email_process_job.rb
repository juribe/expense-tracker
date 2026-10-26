# frozen_string_literal: true

# Backwards-compatible job name for deliveries queued before the MailInbound
# refactor. New deliveries use MailInboundProcessJob.
class InboundEmailProcessJob < MailInboundProcessJob
end
