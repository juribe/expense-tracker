# frozen_string_literal: true

# WhatsappHelper
# Methods: format_whatsapp_phone, wa_connect_url
#
# Example: format_whatsapp_phone("573001234567") # => "+57 300 123 4567"
module WhatsappHelper
  # The first message the user sends from the number they want to link. The
  # single-use CONNECT token travels in the same message so the sender number
  # is bound to the signed-in account, never to whoever sent the greeting.
  INITIAL_MESSAGE = "Hola yogasto quiero registrar mis gastos usando whatsapp"

  def format_whatsapp_phone(digits)
    normalized = WhatsappIdentity.normalize(digits)
    return "+#{normalized}" unless normalized.match?(/\A\d{12}\z/) && normalized.start_with?("57")

    "+#{normalized[0, 2]} #{normalized[2, 3]} #{normalized[5, 3]} #{normalized[8, 4]}"
  end

  # Deep link that opens the business chat with the initial greeting and the
  # CONNECT token prefilled. The token is what proves number ownership.
  def wa_connect_url(code)
    business_number = ENV["WHATSAPP_BUSINESS_NUMBER"].to_s.gsub(/\D/, "")
    return "#" if business_number.blank?

    message = "#{INITIAL_MESSAGE}\n\nCONNECT #{code}"
    "https://wa.me/#{business_number}?text=#{CGI.escape(message)}"
  end
end
