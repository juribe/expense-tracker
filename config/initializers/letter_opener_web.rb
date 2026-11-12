# frozen_string_literal: true

# letter_opener_web renders its Bootstrap styles as inline <style> tags. The
# application's strict CSP blocks inline styles, so relax style-src only for
# the development mail preview controller.
if Rails.env.development?
  Rails.application.config.to_prepare do
    controller = LetterOpenerWeb::ApplicationController
    next if controller.instance_variable_get(:@letter_opener_web_csp_configured)

    controller.content_security_policy do |policy|
      policy.style_src :self, :unsafe_inline
    end
    controller.instance_variable_set(:@letter_opener_web_csp_configured, true)
  end
end
