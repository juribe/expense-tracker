# Be sure to restart your server when you modify this file.

Rails.application.configure do
  # 'unsafe-inline' remains in style-src only because the views still carry
  # inline style= attributes; the script-src directive is fully strict now
  # that all application JavaScript lives in modules.
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.img_src :self, :data, :https
    policy.font_src :self, "https://fonts.gstatic.com"
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
    policy.script_src :self, "https://cdn.jsdelivr.net"
    policy.connect_src :self
    policy.object_src :none
    policy.form_action :self
    policy.frame_src :self
    policy.frame_ancestors :self
  end
end
