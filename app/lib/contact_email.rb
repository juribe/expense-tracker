# frozen_string_literal: true

# ContactEmail
# Centralized destination and sender for the public Contáctanos form.
#
# The internal inbox is never rendered in the public page; it is read at
# delivery time so deployments can change it without a code change.
#
# Example:
#   ContactEmail.recipient # => "hola@yogasto.co"
#   ContactEmail.sender    # => "no-reply@yogasto.co"
module ContactEmail
  DEFAULT_RECIPIENT = "hola@yogasto.co"
  DEFAULT_SENDER = "no-reply@yogasto.co"

  module_function

  def recipient
    ENV["CONTACT_EMAIL"].presence || DEFAULT_RECIPIENT
  end

  def sender
    ENV["CONTACT_FROM_EMAIL"].presence || DEFAULT_SENDER
  end
end
