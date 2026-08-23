# frozen_string_literal: true

require "test_helper"

class EmailTransactionDetectorTest < ActiveSupport::TestCase
  def detector
    @detector ||= EmailTransactionDetector.new
  end

  def detection(subject, body)
    detector.call(subject: subject, body: body)
  end

  test "flags a card purchase notification as transactional" do
    result = detection(
      "Compra aprobada",
      "Compra realizada por $48.500 en RESTAURANTE XYZ con tarjeta terminada en 1234."
    )
    assert result.transactional?
    assert_nil result.reason
  end

  test "rejects credit card statements" do
    result = detection("Estado de cuenta agosto", "Tu resumen de tarjeta ya está disponible.")
    assert_not result.transactional?
    assert_equal "credit card statement", result.reason
  end

  test "rejects payment reminders and minimum payment notices" do
    result = detection("Recordatorio de pago", "Recuerda pagar al menos el pago mínimo antes del 5.")
    assert_not result.transactional?
    assert_equal "payment reminder", result.reason
  end

  test "rejects promotions and marketing emails" do
    result = detection("¡Gran promoción!", "50% de descuento solo hoy. Responde a este correo.")
    assert_not result.transactional?
    assert_equal "promotion or marketing", result.reason
  end

  test "rejects balance notifications" do
    result = detection("Consulta de saldo", "Tu saldo disponible es $100.000.")
    assert_not result.transactional?
    assert_equal "account balance notification", result.reason
  end

  test "rejects security notifications" do
    result = detection("Alerta de seguridad", "Detectamos un inicio de sesión desde un nuevo dispositivo.")
    assert_not result.transactional?
    assert_equal "security notification", result.reason
  end

  test "identifies refunds as special non-expense cases" do
    result = detection("Reembolso realizado", "Hemos acreditado un reembolso de $20.000.")
    assert_not result.transactional?
    assert_equal "refund", result.reason
  end

  test "identifies reversed transactions" do
    result = detection("Transacción reversada", "La compra fue reversada por el comercio.")
    assert_not result.transactional?
    assert_equal "reversed transaction", result.reason
  end

  test "identifies failed transactions" do
    result = detection("Compra rechazada", "Tu transacción fue rechazada por fondos insuficientes.")
    assert_not result.transactional?
    assert_equal "failed transaction", result.reason
  end
end
