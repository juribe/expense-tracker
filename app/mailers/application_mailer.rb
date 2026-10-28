class ApplicationMailer < ActionMailer::Base
  helper :mailer
  helper_method :greeting_name, :greeting
  layout "mailer"

  def default_url_options
    { host: (Rails.application.config.action_mailer.default_url_options&.fetch(:host, "example.com") || "example.com") }
  end

  def greeting_name(resource)
    MailerHelper.greeting_name(resource)
  end

  def greeting(resource)
    MailerHelper.greeting(resource)
  end
end