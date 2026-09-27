# frozen_string_literal: true

# Formats normalized WhatsApp digits for display: Colombian numbers (57 +
# 10 digits) render as "+57 300 123 4567"; anything else as "+<digits>".
module WhatsappHelper
  def format_whatsapp_phone(digits)
    normalized = WhatsappIdentity.normalize(digits)
    return "+#{normalized}" unless normalized.match?(/\A\d{12}\z/) && normalized.start_with?("57")

    "+#{normalized[0, 2]} #{normalized[2, 3]} #{normalized[5, 3]} #{normalized[8, 4]}"
  end

  # Deep link that opens the business chat with the CONNECT command prefilled.
  def wa_connect_url(code)
    business_number = ENV["WHATSAPP_BUSINESS_NUMBER"].to_s.gsub(/\D/, "")
    return "#" if business_number.blank?

    "https://wa.me/#{business_number}?text=#{CGI.escape("CONNECT #{code}")}"
  end
end
