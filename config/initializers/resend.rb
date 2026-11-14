# frozen_string_literal: true

# Outbound transactional email uses Resend in production (see
# config/environments/production.rb). The gem keeps a single global key, which
# Resend::Mailer reads when it delivers. Inbound receiving passes its own
# explicit key in MailInbound::Providers::Resend::ReceivingClient.
#
# Example:
#   RESEND_API_KEY=re_... bin/rails runner "Resend.api_key"
Resend.api_key = ENV["RESEND_API_KEY"] if ENV["RESEND_API_KEY"].present?

if Rails.env.production? && ENV["RESEND_API_KEY"].blank? && ENV["SMTP_ADDRESS"].blank?
  Rails.logger&.warn "RESEND_API_KEY and SMTP_ADDRESS are unset: production email will not be delivered."
end
