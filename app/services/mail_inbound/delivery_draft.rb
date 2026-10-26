# frozen_string_literal: true

module MailInbound
  # DeliveryDraft
  # Provider-independent data persisted before enqueueing MailInboundHandleJob.
  DeliveryDraft = Data.define(:provider, :external_id, :raw_body, :headers, :params, :user)
end
