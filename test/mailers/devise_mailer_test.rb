# frozen_string_literal: true

require "test_helper"

class DeviseMailerTest < ActionMailer::TestCase
  include Rails.application.routes.url_helpers
  setup do
    @user = User.create!(
      name: "  José Uribe  ",
      email: "jose.mailer@example.com",
      password: "password123"
    )
    @token = @user.send_reset_password_instructions
    @mail = Devise::Mailer.reset_password_instructions(@user, @token)
  end

  test "reset password subject is unchanged" do
    assert_equal "Instrucciones para restablecer la contraseña", @mail.subject
  end

  test "reset password html uses name greeting" do
    html = @mail.html_part.body.to_s
    assert_includes html, "¡Hola, José Uribe!"
  end

  test "reset password text uses name greeting" do
    text = @mail.text_part.body.to_s
    assert_includes text, "¡Hola, José Uribe!"
  end

  test "the footer uses APP_NAME for branding" do
    html = nil
    with_env("APP_NAME" => "Mis Gastos") do
      html = Devise::Mailer.reset_password_instructions(@user, @token).html_part.body.to_s
    end

    assert_includes html, "© #{Date.current.year} Mis Gastos · Tus finanzas, más claras."
  end

  test "reset password contains required content" do
    html = @mail.html_part.body.to_s
    assert_includes html, "Restablece tu contraseña"
    assert_includes html, "Recibimos una solicitud para cambiar la contraseña de tu cuenta. Haz clic en el botón para crear una nueva."
    assert_includes html, "Cambiar mi contraseña"
    assert_includes html, "Si no solicitaste este cambio, puedes ignorar este correo. Tu contraseña seguirá siendo la misma."
    assert_includes html, "© #{Date.current.year} #{AppName.current} · Tus finanzas, más claras."
    assert_includes html, "Este es un correo automático; por favor, no respondas a este mensaje."
  end

  test "reset password button uses generated link" do
    expected = Rails.application.routes.url_helpers.edit_user_password_url(reset_password_token: @token, host: "example.com")
    assert_includes @mail.html_part.body.to_s, expected
    assert_includes @mail.text_part.body.to_s, expected
  end

  test "greeting uses email when name is nil" do
    user = User.new(name: nil, email: "nilname@example.com", password: "password123")
    mail = Devise::Mailer.reset_password_instructions(user, "sometoken")
    assert_includes mail.html_part.body.to_s, "¡Hola, nilname@example.com!"
    assert_includes mail.text_part.body.to_s, "¡Hola, nilname@example.com!"
  end

  test "greeting uses email when name is blank or spaces" do
    user = User.create!(name: "   ", email: "blankname@example.com", password: "password123")
    mail = Devise::Mailer.reset_password_instructions(user, user.send_reset_password_instructions)
    assert_includes mail.html_part.body.to_s, "¡Hola, blankname@example.com!"
    assert_includes mail.text_part.body.to_s, "¡Hola, blankname@example.com!"
  end

  test "greeting strips surrounding spaces" do
    user = User.create!(name: "  Ana  ", email: "ana@example.com", password: "password123")
    mail = Devise::Mailer.reset_password_instructions(user, user.send_reset_password_instructions)
    assert_includes mail.html_part.body.to_s, "¡Hola, Ana!"
    refute_includes mail.html_part.body.to_s, "¡Hola,   Ana  !"
  end
end
