# frozen_string_literal: true

require "test_helper"

# ContactMailer delivers a visitor's Contáctanos message to the configured
# internal recipient. The visitor's address becomes the Reply-To header.
class ContactMailerTest < ActionMailer::TestCase
  def contact_params
    {
      name: "Ana Pérez",
      email: "ana@example.com",
      subject: "Necesito soporte",
      message: "No puedo registrar un gasto."
    }
  end

  test "envía al destinatario configurado con reply-to del visitante" do
    email = ContactMailer.with(contact_params).new_message

    assert_equal [ "hola@yogasto.co" ], email.to
    assert_equal [ "no-reply@yogasto.co" ], email.from
    assert_equal [ "ana@example.com" ], email.reply_to
    assert_equal "Nuevo mensaje de contacto: Necesito soporte", email.subject
  end

  test "incluye nombre, correo, motivo y mensaje en HTML y texto" do
    email = ContactMailer.with(contact_params).new_message

    [ email.html_part.body.to_s, email.text_part.body.to_s ].each do |body|
      assert_match "Ana Pérez", body
      assert_match "ana@example.com", body
      assert_match "Necesito soporte", body
      assert_match "No puedo registrar un gasto.", body
    end
  end

  test "lee destinatario y remitente desde variables de entorno" do
    with_env("CONTACT_EMAIL" => "soporte@test.co", "CONTACT_FROM_EMAIL" => "contacto@test.co") do
      email = ContactMailer.with(contact_params).new_message

      assert_equal [ "soporte@test.co" ], email.to
      assert_equal [ "contacto@test.co" ], email.from
    end
  end

  test "el correo de contacto no muestra el aviso de no responder" do
    email = ContactMailer.with(contact_params).new_message
    html = email.html_part.body.to_s

    refute_match "no respondas", html
    assert_match "Puedes responder", html
  end
end
