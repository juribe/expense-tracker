class ApplicationMailer < ActionMailer::Base
  helper :mailer
  helper_method :greeting_name, :greeting
  layout "mailer"

  def default_url_options
    options = (Rails.application.config.action_mailer.default_url_options || {}).dup
    options[:host] = ENV["APP_HOST"] if ENV["APP_HOST"].present?
    options[:protocol] ||= "https" if Rails.env.production?
    options.presence || { host: "localhost", port: 3000 }
  end

  def greeting_name(resource)
    MailerHelper.greeting_name(resource)
  end

  def greeting(resource)
    MailerHelper.greeting(resource)
  end
end