# frozen_string_literal: true

# MailInboundService
# Single entry point for inbound email webhooks. Provider-specific signature
# validation, delivery persistence and email normalization live in
# MailInbound::Providers.
class MailInboundService
  def initialize(provider: MailInbound.provider_name)
    @provider = MailInbound.provider_class(provider).new
  end

  attr_reader :provider

  def valid_signature?(request)
    provider.valid_signature?(request)
  end

  def accept(request)
    return MailInbound::Result.new(status: :invalid_signature) unless valid_signature?(request)

    draft = provider.build_delivery(request)
    delivery = find_or_initialize_delivery(draft)
    return MailInbound::Result.new(status: :duplicate, delivery: delivery) if duplicate?(delivery)

    persist_delivery(delivery, draft)
    enqueue_handle(delivery)
    MailInbound::Result.new(status: :accepted, delivery: delivery)
  rescue MailInbound::ConfigurationError => e
    MailInbound::Result.new(status: :configuration_error, error: e)
  rescue MailInbound::UnsupportedMediaType => e
    MailInbound::Result.new(status: :unsupported_media_type, error: e)
  rescue MailInbound::PayloadTooLarge => e
    MailInbound::Result.new(status: :payload_too_large, error: e)
  rescue MailInbound::UnknownRecipient => e
    MailInbound::Result.new(status: :unknown_recipient, error: e)
  rescue MailInbound::InvalidPayload => e
    MailInbound::Result.new(status: :invalid_payload, error: e)
  rescue MailInbound::QueueError => e
    MailInbound::Result.new(status: :queue_unavailable, delivery: delivery, error: e)
  rescue ActiveRecord::RecordNotUnique
    delivery = MailInboundDelivery.find_by!(
      provider: draft.provider, external_id: draft.external_id
    )
    MailInbound::Result.new(status: :duplicate, delivery: delivery)
  end

  def handle_email(delivery)
    provider.handle_email(delivery)
  end

  private

  def find_or_initialize_delivery(draft)
    MailInboundDelivery.find_or_initialize_by(
      provider: draft.provider,
      external_id: draft.external_id
    )
  end

  def duplicate?(delivery)
    return false unless delivery.persisted?
    return false if delivery.status == "failed"
    return false if stale_handling?(delivery)

    true
  end

  def stale_handling?(delivery)
    delivery.status == "handling" && delivery.updated_at < MailInboundDelivery::STALE_HANDLING_TIMEOUT.ago
  end

  def persist_delivery(delivery, draft)
    delivery.assign_attributes(
      user: draft.user,
      raw_body: draft.raw_body,
      headers: draft.headers,
      params: draft.params,
      status: "received",
      last_error: nil,
      processed_at: nil
    )
    delivery.save!
  end

  def enqueue_handle(delivery)
    MailInboundHandleJob.perform_later(delivery.id)
  rescue StandardError
    delivery.failed!("could not enqueue handle job")
    raise MailInbound::QueueError, "could not enqueue inbound handle job"
  end
end
