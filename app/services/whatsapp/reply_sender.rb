# frozen_string_literal: true

require "net/http"

# Whatsapp::ReplySender
# Sends text replies back to a WhatsApp user through the Meta Cloud API, using
# the business phone number and system user token configured via ENV. Safe to
# call without credentials: it logs and no-ops instead of raising, so webhook
# processing never depends on outbound delivery.
#
# Example: Whatsapp::ReplySender.send_to("573001234567", "WhatsApp conectado ✅")
module Whatsapp
  class ReplySender
    GRAPH_URL = "https://graph.facebook.com/v23.0"
    MAX_DELIVERY_ATTEMPTS = 3

    def self.send_to(phone_number, text)
      payload = {
        messaging_product: "whatsapp",
        to: phone_number,
        type: "text",
        text: { body: text }
      }
      deliver(phone_number, payload)
    end

    # Interactive list message: a short header plus up to 10 tappable rows,
    # with the full question in the body.
    #   rows: [{ id: "source:23", title: "Davibank", description: nil }]
    # WhatsApp limits: header text ≤ 60 chars, row title ≤ 24, description ≤
    # 72; the full question travels in the body.
    def self.send_list(phone_number, text, rows, button_label: "Elegir", header: "Información faltante")
      raise ArgumentError, "list rows must be 1..10" if rows.blank? || rows.size > 10

      text = text.to_s
      payload = {
        messaging_product: "whatsapp",
        to: phone_number,
        type: "interactive",
        interactive: {
          type: "list",
          header: { type: "text", text: header.to_s[0, 60].presence || "Información faltante" },
          body: { text: text[0, 1024] },
          action: {
            button: button_label,
            sections: [ { title: "Opciones", rows: rows.map do |row|
              { id: row[:id], title: row[:title].to_s[0, 24], description: row[:description].to_s[0, 72].presence }.compact
            end } ]
          }
        }
      }
      deliver(phone_number, payload)
    end

    # Interactive button message: up to 3 quick-reply buttons (title ≤ 20
    # chars) with the question in the body. Deterministic taps, no LLM.
    #   buttons: [{ id: "newcategory:yes", title: "Sí, crear" }]
    def self.send_buttons(phone_number, text, buttons, header: "Confirmación")
      raise ArgumentError, "buttons must be 1..3" if buttons.blank? || buttons.size > 3

      text = text.to_s
      payload = {
        messaging_product: "whatsapp",
        to: phone_number,
        type: "interactive",
        interactive: {
          type: "button",
          header: { type: "text", text: header.to_s[0, 60].presence || "Confirmación" },
          body: { text: text[0, 1024] },
          action: {
            buttons: buttons.map do |button|
              { type: "reply", reply: { id: button[:id], title: button[:title].to_s[0, 20] } }
            end
          }
        }
      }
      deliver(phone_number, payload)
    end

    def self.deliver(phone_number, payload)
      token = ENV["WHATSAPP_ACCESS_TOKEN"]
      phone_number_id = ENV["WHATSAPP_BUSINESS_PHONE_NUMBER_ID"]

      if token.blank? || phone_number_id.blank?
        Rails.logger.warn "[ReplySender] WHATSAPP_ACCESS_TOKEN/WHATSAPP_BUSINESS_PHONE_NUMBER_ID missing; reply skipped"
        return false
      end

      uri = URI("#{GRAPH_URL}/#{phone_number_id}/messages")
      body = payload.merge(messaging_product: "whatsapp", to: phone_number).to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{token}")

      response_code = deliver_with_retries(http, request, body, phone_number)
      unless response_code == "200"
        Rails.logger.error "[ReplySender] Failed to deliver reply to #{phone_number}: #{response_code}"
        return false
      end
      Rails.logger.info "[ReplySender] Delivered #{payload.dig(:interactive) ? 'list' : 'text'} " \
                        "to #{phone_number} (#{body.bytesize} bytes)"
      true
    end

    # Transient Meta API failures (service unavailable, throttling, rate
    # limits, network timeouts) are retried with a doubling backoff;
    # permanent client errors (auth, payload, permissions) are not.
    def self.deliver_with_retries(http, request, body, phone_number)
      attempts = 0
      delay = 1
      loop do
        attempts += 1
        code = request_code(http, request, body)
        return code if code == "200" || !transient?(code)
        return "gave_up" if attempts >= MAX_DELIVERY_ATTEMPTS

        Rails.logger.warn "[ReplySender] Transient failure (#{code}) for #{phone_number}, " \
                          "attempt #{attempts}/#{MAX_DELIVERY_ATTEMPTS}"
        sleep(delay)
        delay *= 2
      end
    end

    def self.request_code(http, request, body)
      http.request(request, body).code
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED, SocketError
      "timeout"
    end

    def self.transient?(code)
      code.start_with?("5") || code == "429" || code == "408" || code == "timeout"
    end

    def self.sleep(seconds)
      Kernel.sleep(seconds)
    end
  end
end
