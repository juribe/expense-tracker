# Be sure to restart your server when you modify this file.

Rails.application.configure do
  # Defense-in-depth baseline. 'unsafe-inline' stays for script/style because
  # the ERB templates still carry legacy inline scripts; it must be dropped
  # once the application JavaScript is fully moved into modules.
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.img_src :self, :data, :https
    policy.font_src :self, "https://fonts.gstatic.com"
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline
    policy.script_src :self, "https://cdn.jsdelivr.net", :unsafe_inline
    policy.connect_src :self
    policy.object_src :none
    policy.form_action :self
    policy.frame_src :self
    policy.frame_ancestors :self
  end
end
