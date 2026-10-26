# frozen_string_literal: true

module MailInbound
  # Message
  # Provider-neutral email data returned by every inbound provider.
  Message = Data.define(
    :provider,
    :external_id,
    :from,
    :to,
    :subject,
    :body_text,
    :html,
    :headers,
    :attachments,
    :internal_date,
    :recipient,
    :user
  ) do
    def to_payload
      to_h.merge(id: external_id).deep_stringify_keys.as_json
    end
  end
end
