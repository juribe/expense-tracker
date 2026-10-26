# frozen_string_literal: true

module MailInbound
  # RecipientResolver
  # Resolves receive+token@domain to a User through configuration.
  #
  #   MailInbound::RecipientResolver.new(recipient: "receive+user1@example.com").user
  class RecipientResolver
    def initialize(recipient:,
                   base_recipient: ENV["INBOUND_EMAIL_RECIPIENT"],
                   user_email: ENV["INBOUND_EMAIL_USER_EMAIL"],
                   user_map: ENV["INBOUND_EMAIL_USER_MAP"])
      @recipient = recipient.to_s
      @base_recipient = base_recipient.to_s
      @user_email = user_email.to_s
      @user_map = parse_map(user_map)
    end

    def user
      raise ConfigurationError, "INBOUND_EMAIL_RECIPIENT is not configured" if @base_recipient.blank?
      raise UnknownRecipient, "recipient is not configured" if token.nil?

      # User-specific alias: a plus token that matches a user's stored inbound
      # token identifies that user directly.
      if token.present?
        user_by_token = User.find_by(inbound_email_token: token)
        return user_by_token if user_by_token
      end

      email = mapped_email
      raise UnknownRecipient, "recipient token is not configured" if email.blank? && token.present? && @user_map.any?
      raise ConfigurationError, "INBOUND_EMAIL_USER_EMAIL is not configured" if email.blank?

      User.find_by("LOWER(email) = ?", email.downcase) ||
        raise(ConfigurationError, "inbound email user is not configured")
    end

    def token
      actual = @recipient.strip.downcase
      base = @base_recipient.strip.downcase
      return nil if actual.blank? || base.blank?

      actual_local, actual_domain = actual.split("@", 2)
      base_local, base_domain = base.split("@", 2)
      return nil if [ actual_local, actual_domain, base_local, base_domain ].any?(&:blank?)
      return nil unless actual_domain == base_domain
      return "" if actual_local == base_local

      prefix = "#{base_local}+"
      return actual_local.delete_prefix(prefix) if actual_local.start_with?(prefix) && actual_local.length > prefix.length

      nil
    end

    private

    def mapped_email
      return @user_email.presence if token.blank? || @user_map.empty?

      @user_map[token]
    end

    def parse_map(value)
      value.to_s.split(/[,\n]/).each_with_object({}) do |entry, map|
        token, email = entry.split("=", 2).map(&:strip)
        map[token.downcase] = email if token.present? && email.present?
      end
    end
  end
end
