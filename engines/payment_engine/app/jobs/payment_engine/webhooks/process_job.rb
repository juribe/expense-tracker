module PaymentEngine
  module Webhooks
    class ProcessJob < ApplicationJob
      def perform(webhook_event_id)
        event = WebhookEvent.find(webhook_event_id)
        Processor.call(event)
      end
    end
  end
end
