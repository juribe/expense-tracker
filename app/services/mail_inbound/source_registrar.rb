# frozen_string_literal: true

module MailInbound
  # Registers inbound email senders as forwarding sources that must be
  # explicitly accepted before their messages are processed.
  class SourceRegistrar
    def self.origin_email(message)
      data = message.is_a?(Hash) ? message : (message.respond_to?(:to_h) ? message.to_h : {})
      data = data.symbolize_keys
      from = data[:from].to_s
      match = from.match(/<([^>]+)>/) || from.match(/([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})/i)
      (match ? match[1] : from).to_s.strip.downcase.presence
    end

    def self.find_or_register(user, origin)
      return nil if origin.blank?

      source = user.email_sources.forwarding.where("LOWER(email) = ?", origin).first
      return source if source

      user.email_sources.create!(
        source_type: "forwarding",
        email: origin,
        status: "pending_setup"
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      user.email_sources.forwarding.where("LOWER(email) = ?", origin).first
    end

    def self.allowed?(user, message)
      origin = origin_email(message)
      source = user.email_sources.forwarding.where("LOWER(email) = ?", origin).first
      source&.active?
    end
  end

  SourceRegistrar = SourceRegistrar
end

# Top-level aliases
EmailSourceRegistrar = MailInbound::SourceRegistrar unless defined?(::EmailSourceRegistrar)
SourceRegistrar = MailInbound::SourceRegistrar unless defined?(::SourceRegistrar)