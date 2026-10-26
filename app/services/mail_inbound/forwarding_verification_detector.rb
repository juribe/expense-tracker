# frozen_string_literal: true

module MailInbound
  # Detects Gmail forwarding verification messages received through the inbound
  # pipeline and stores them temporarily for the owning user. These messages
  # must never be processed as financial transactions.
  class ForwardingVerificationDetector
    GOOGLE_SENDERS = [
      "forwarding-noreply@google.com",
      "mail-noreply@google.com",
      "noreply@google.com"
    ].freeze

    CONFIRMATION_TEXT_TERMS = %w[accept confirm verify aceptar confirmar verificar].freeze
    FORWARDING_TEXT_TERMS = %w[forward forwarding reenvío reenvio reenviar redirección redireccion].freeze
    CANCEL_TEXT_TERMS = %w[cancel cancelar decline rechazar unsubscribe].freeze
    CONFIRMATION_PATH_TERMS = %w[confirm verify forward vf-].freeze
    MIN_CONFIRMATION_SCORE = 3

    def self.verification_message?(message)
      data = normalize(message)
      from = data[:from].to_s.downcase
      subject = data[:subject].to_s.downcase
      body = "#{data[:body_text]} #{data[:html]}".to_s.downcase

      google_sender = GOOGLE_SENDERS.any? { |sender| from.include?(sender) } || from.include?("google.com")

      forwarding_terms = %w[forwarding forward reenvío reenvio reenviar redirección redireccion]
      verification_terms = %w[confirm confirmación confirmation verification verify verificación verificar]
      forwarding = forwarding_terms.any? { |term| subject.include?(term) || body.include?(term) }
      verification = verification_terms.any? { |term| subject.include?(term) || body.include?(term) }

      google_sender && forwarding && verification
    end

    def self.extract_code(message)
      data = normalize(message)
      text = "#{data[:subject]} #{data[:body_text]} #{data[:html]}"
      match = text.match(/confirmation code[:\s]*([A-Za-z0-9-]+)/i) ||
              text.match(/code[:\s]+([A-Za-z0-9-]+)/i)
      match && match[1]
    end

    def self.extract_confirmation_url(message)
      data = normalize(message)
      url = extract_from_html(data[:html]) || extract_from_text(data[:body_text], data[:html])
      ConfirmationUrlValidator.call(url)
    end

    def self.extract_from_html(html)
      return nil if html.blank?

      document = Nokogiri::HTML(html.to_s)
      candidates = document.css("a[href]").each_with_index.filter_map do |anchor, index|
        safe_url = ConfirmationUrlValidator.call(anchor["href"])
        next if safe_url.nil?

        score = anchor_score(safe_url, anchor)
        next if score < MIN_CONFIRMATION_SCORE

        [ score, -index, safe_url ]
      end

      candidates.max_by { |score, position, _url| [ score, position ] }&.last
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    def self.extract_from_text(body_text, html)
      text = body_text.to_s
      text += " #{Nokogiri::HTML(html.to_s).text}" if html.present?

      candidates = text.scan(%r{https?://[^\s"'<>]+}).filter_map do |url|
        safe_url = ConfirmationUrlValidator.call(url)
        next if safe_url.nil?

        score = confirmation_path?(safe_url) ? MIN_CONFIRMATION_SCORE : 1
        [ score, safe_url ]
      end

      candidates.max_by(&:first)&.last
    rescue Nokogiri::XML::SyntaxError
      nil
    end

    def self.anchor_score(url, anchor)
      text = [ anchor.text, anchor["aria-label"], anchor["title"] ].compact.join(" ").downcase
      score = 0
      score += 3 if CONFIRMATION_TEXT_TERMS.any? { |term| text.include?(term) }
      score += 2 if FORWARDING_TEXT_TERMS.any? { |term| text.include?(term) }
      score -= 3 if CANCEL_TEXT_TERMS.any? { |term| text.include?(term) }
      score += 2 if confirmation_path?(url)
      score + 1
    end

    def self.confirmation_path?(url)
      CONFIRMATION_PATH_TERMS.any? { |term| url.to_s.downcase.include?(term) }
    end

    def self.store!(user:, message:, processed_email: nil, email_source: nil)
      data = normalize(message)
      source = email_source || matching_source_for(user, data[:subject])

      EmailForwardingVerification.create!(
        user: user,
        email_source: source,
        code: extract_code(data),
        confirmation_url: extract_confirmation_url(data),
        sender_email: data[:from],
        subject: data[:subject],
        message_id: data[:id] || data[:external_id] || data[:message_id],
        expires_at: 7.days.from_now
      )
    end

    def self.matching_source_for(user, subject)
      origin_email = EmailForwardingVerification.origin_email_from_subject(subject)
      return pending_source_for(user) if origin_email.blank?

      user.email_sources.forwarding.where("LOWER(email) = ?", origin_email.downcase).first
    end

    def self.pending_source_for(user)
      user.email_sources.forwarding.where(status: %w[pending_setup pending_verification]).order(:created_at).last
    end

    def self.normalize(message)
      return {} if message.blank?

      hash = if message.is_a?(Hash)
               message
      elsif message.respond_to?(:to_h)
               message.to_h
      else
               {}
      end
      hash.symbolize_keys
    rescue StandardError
      {}
    end
    private_class_method :extract_from_html, :extract_from_text, :anchor_score,
                         :confirmation_path?, :matching_source_for, :normalize

    # Convenience aliases.
    class << self
      alias detect verification_message?
      alias detect? verification_message?
      alias verification? verification_message?
    end
  end

  # Aliases for alternative naming used by callers/tests.
  GmailForwardingVerificationDetector = ForwardingVerificationDetector
end

# Top-level aliases for callers/tests that omit the MailInbound namespace.
ForwardingVerificationDetector = MailInbound::ForwardingVerificationDetector unless defined?(::ForwardingVerificationDetector)
EmailForwardingVerificationDetector = MailInbound::ForwardingVerificationDetector unless defined?(::EmailForwardingVerificationDetector)
GmailForwardingVerificationDetector = MailInbound::ForwardingVerificationDetector unless defined?(::GmailForwardingVerificationDetector)
