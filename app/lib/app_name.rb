# frozen_string_literal: true

# Branding for the text we send to users (WhatsApp replies, AI prompts).
# APP_NAME lets deployments rename the product without code changes. It is read
# on every call so runtime overrides and tests take effect immediately.
module AppName
  DEFAULT = "Yogasto"

  module_function

  def current
    ENV.fetch("APP_NAME", DEFAULT)
  end
end
