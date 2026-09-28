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
      response = http.request(request, body)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error "[ReplySender] Failed to deliver reply to #{phone_number}: #{response.code} #{response.body}"
        return false
      end
      true
    rescue StandardError => e
      Rails.logger.error "[ReplySender] Error sending reply to #{phone_number}: #{e.message}"
      false
    end
  end
end
