# frozen_string_literal: true

require "test_helper"

# ContactMessage is the server-side form object for Contáctanos. It owns the
# validation and normalization rules so the controller never trusts the client.
class ContactMessageTest < ActiveSupport::TestCase
  def valid_attributes
    {
      name: "  Ana Pérez  ",
      email: "  ANA@Example.COM ",
      subject: "  Necesito soporte  ",
      message: "  No puedo registrar un gasto.  "
    }
  end

  test "acepta un mensaje completo y normaliza sus datos" do
    message = ContactMessage.new(valid_attributes)

    assert message.valid?
    assert_equal "Ana Pérez", message.name
    assert_equal "ana@example.com", message.email
    assert_equal "Necesito soporte", message.subject
    assert_equal "No puedo registrar un gasto.", message.message
    refute message.spam?
    assert_equal(
      {
        name: "Ana Pérez",
        email: "ana@example.com",
        subject: "Necesito soporte",
        message: "No puedo registrar un gasto."
      },
      message.delivery_params
    )
  end

  test "exige nombre, correo, motivo y mensaje" do
    message = ContactMessage.new

    refute message.valid?
    %i[name email subject message].each do |attribute|
      assert message.errors[attribute].any?, "Se esperaba un error en #{attribute}"
    end
  end

  test "rechaza correos con formato inválido" do
    [ "no-es-un-correo", "ana@", "@example.com", "ana example.com" ].each do |email|
      message = ContactMessage.new(valid_attributes.merge(email: email))

      refute message.valid?, "#{email} no debería ser válido"
      assert message.errors[:email].any?
    end
  end

  test "limita la longitud de los campos" do
    {
      name: "a" * 121,
      email: "#{"a" * 250}@example.com",
      subject: "a" * 121,
      message: "a" * 5001
    }.each do |attribute, value|
      message = ContactMessage.new(valid_attributes.merge(attribute => value))

      refute message.valid?, "#{attribute} excedido debería ser inválido"
      assert message.errors[attribute].any?
    end
  end

  test "rechaza saltos de línea en el motivo" do
    message = ContactMessage.new(
      valid_attributes.merge(subject: "Soporte\r\nBcc: evil@example.com")
    )

    refute message.valid?
    assert message.errors[:subject].any?
  end

  test "detecta el honeypot como spam" do
    message = ContactMessage.new(valid_attributes.merge(website: "https://spam.example"))

    assert message.spam?
  end
end
