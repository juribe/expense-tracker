# frozen_string_literal: true

# ContactMailer
# Delivers a visitor's Contáctanos message to the internal inbox configured
# through ContactEmail. The visitor's address is used as Reply-To so the team
# can answer directly from the email client.
#
# Example:
#   ContactMailer.with(name: "Ana", email: "ana@example.com",
#                      subject: "Soporte", message: "Hola").new_message.deliver_later
class ContactMailer < ApplicationMailer
  default from: -> { ContactEmail.sender }

  def new_message
    @contact_name = params[:name]
    @contact_email = params[:email]
    @contact_subject = params[:subject].to_s.gsub(/[\r\n]+/, " ").strip
    @contact_message = params[:message]
    @allow_reply = true

    mail(
      to: ContactEmail.recipient,
      reply_to: @contact_email,
      subject: "Nuevo mensaje de contacto: #{@contact_subject}"
    )
  end
end
