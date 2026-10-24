# Be sure to restart your server when you modify this file.

Rails.application.configure do
  # Fully strict now: all application JavaScript lives in modules and all
  # view styles moved to stylesheets. Chart pages (dashboard, the Chartkick
  # reports) relax style-src per action because Chartkick/Chart.js inject
  # chart markup with inline styles. The nonce generator lets Chartkick's
  # generated inline chart scripts execute under the strict script-src.
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.img_src :self, :data, :https
    policy.font_src :self, "https://fonts.gstatic.com"
    policy.style_src :self, "https://fonts.googleapis.com"
    policy.script_src :self, "https://cdn.jsdelivr.net"
    policy.connect_src :self
    policy.object_src :none
    policy.form_action :self
    policy.frame_src :self
    policy.frame_ancestors :self
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
