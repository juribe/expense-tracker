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

  def format_whatsapp_phone(phone_number)
    digits = WhatsappIdentity.wa_id(phone_number)
    return "" if digits.blank?
    return "+#{digits}" unless digits.match?(/\A57\d{10}\z/)

    "+#{digits[0, 2]} #{digits[2, 3]} #{digits[5, 3]} #{digits[8, 4]}"
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
