# frozen_string_literal: true

# MailerHelper
# Methods: greeting_name, greeting
#
# Example: greeting(user) # => "¡Hola, José!"
module MailerHelper
  def greeting_name(resource)
    name = resource.try(:name).to_s.strip
    name.present? ? name : resource.email
  end

  def greeting(resource)
    "¡Hola, #{greeting_name(resource)}!"
  end

  alias greeting_for greeting
  alias user_greeting greeting
  alias mailer_greeting greeting
  alias recipient_name greeting_name
  alias user_display_name greeting_name
  alias display_name greeting_name

  extend self
end