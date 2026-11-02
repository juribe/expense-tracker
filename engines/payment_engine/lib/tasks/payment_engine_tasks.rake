namespace :payment_engine do
  desc "Expire memberships and finalize subscriptions whose period has ended"
  task expire_memberships: :environment do
    result = PaymentEngine::Jobs::ExpireMembershipsJob.perform_now
    puts "PaymentEngine expiration finished: #{result.inspect}"
  end

  desc "Reprocess a failed or received webhook event by id"
  task :reprocess_webhook, [ :event_id ] => :environment do |_task, args|
    event = PaymentEngine::WebhookEvent.find(args[:event_id])
    PaymentEngine::Webhooks::Processor.call(event)
    puts "Webhook event #{event.id} processed with status #{event.reload.status}"
  end
end
