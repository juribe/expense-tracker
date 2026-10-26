# frozen_string_literal: true

require "cgi"
require "digest"
require "mail"

module MailInbound
  # MessageParser
  # Normalizes the raw RFC 5322/MIME body forwarded by the Cloudflare Worker
  # into the hash consumed by the existing email import pipeline.
  #
  #   message = MailInbound::MessageParser.call(raw, envelope_from:, envelope_to:)
  #   message[:body_text] # => "Compra aprobada..."
  class MessageParser
    MAX_BODY_BYTES = 2 * 1024 * 1024

    class Error < StandardError; end

    class << self
      def call(raw, envelope_from:, envelope_to:)
        new(raw, envelope_from: envelope_from, envelope_to: envelope_to).call
      end
    end

    def initialize(raw, envelope_from:, envelope_to:)
      @raw = raw.to_s
      @envelope_from = envelope_from.to_s
      @envelope_to = envelope_to.to_s
    end

    def call
      raise Error, "empty email body" if @raw.blank?

      mail = Mail.read_from_string(@raw)
      html = truncate_body(html_body(mail))
      text = truncate_body(text_body(mail))
      text = truncate_body(strip_html(html)) if text.blank? && html.present?

      {
        id: message_id(mail),
        from: sender(mail),
        to: recipients(mail),
        subject: mail.subject.to_s,
        body_text: text,
        html: html.presence,
        internal_date: internal_date(mail),
        snippet: text.to_s[0, 200],
        headers: headers(mail),
        attachments: attachments(mail)
      }
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "unable to parse email (#{e.class})"
    end

    private

    def message_id(mail)
      id = mail.message_id.to_s.strip.presence || "sha256:#{Digest::SHA256.hexdigest(@raw)}"
      id[0, 255]
    end

    def sender(mail)
      mail[:from]&.decoded.presence ||
        Array(mail.from).first.to_s.presence ||
        @envelope_from
    end

    def recipients(mail)
      addresses = Array(mail.to).map(&:to_s).reject(&:blank?)
      addresses.presence || [ @envelope_to ].reject(&:blank?)
    end

    def internal_date(mail)
      date = mail.date
      return Time.current if date.blank?

      date.respond_to?(:to_time) ? date.to_time : Time.zone.parse(date.to_s)
    rescue ArgumentError, TypeError
      Time.current
    end

    def headers(mail)
      mail.header.fields.map do |field|
        {
          "name" => field.name.to_s,
          "value" => field.respond_to?(:decoded) ? field.decoded.to_s : field.value.to_s
        }
      end
    end

    def attachments(mail)
      mail.attachments.map do |attachment|
        {
          "filename" => attachment.filename.to_s,
          "content_type" => attachment.mime_type.to_s,
          "size" => attachment.body.raw_source.to_s.bytesize,
          "content_id" => attachment.content_id.to_s.presence
        }.compact
      end
    end

    def text_body(mail)
      part = mail.text_part
      return safe_decoded(part) if part
      return safe_decoded(mail) if mail.mime_type.to_s == "text/plain"

      nil
    end

    def html_body(mail)
      part = mail.html_part
      return safe_decoded(part) if part
      return safe_decoded(mail) if mail.mime_type.to_s == "text/html"

      nil
    end

    def safe_decoded(part)
      part.body.decoded.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    rescue StandardError
      ""
    end

    def strip_html(html)
      plain = html.to_s
                  .gsub(/<style[^>]*>.*?<\/style>/im, " ")
                  .gsub(/<script[^>]*>.*?<\/script>/im, " ")
                  .gsub(/<[^>]+>/, " ")
      CGI.unescapeHTML(plain).gsub(/\s+/, " ").strip
    end

    def truncate_body(value)
      text = value.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      return text if text.bytesize <= MAX_BODY_BYTES

      text.byteslice(0, MAX_BODY_BYTES).to_s.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
