# frozen_string_literal: true

require "test_helper"

class WhatsappHelperTest < ActionView::TestCase
  test "format_whatsapp_phone formats a Colombian E.164 number" do
    assert_equal "+57 300 123 4567", format_whatsapp_phone("+573001234567")
    assert_equal "+57 300 123 4567", format_whatsapp_phone("573001234567")
  end

  test "format_whatsapp_phone falls back to the E.164 number for other countries" do
    assert_equal "+14155552671", format_whatsapp_phone("+14155552671")
  end
end
