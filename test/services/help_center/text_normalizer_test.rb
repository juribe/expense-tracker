# frozen_string_literal: true

require "test_helper"

class HelpCenterTextNormalizerTest < ActiveSupport::TestCase
  test "quita HTML y normaliza espacios" do
    text = "<p>Cómo registrar un <strong>gasto</strong></p>"

    assert_equal "como registrar un gasto", HelpCenter::TextNormalizer.call(text)
  end

  test "translitega tildes y eñes" do
    assert_equal "nino con credito", HelpCenter::TextNormalizer.call("Niño con crédito")
  end

  test "convierte signos en separadores" do
    assert_equal "como pagar mi membresia", HelpCenter::TextNormalizer.call("¿Cómo pagar mi membresía?")
  end

  test "maneja valores vacíos" do
    assert_equal "", HelpCenter::TextNormalizer.call(nil)
    assert_equal "", HelpCenter::TextNormalizer.call("")
  end
end
