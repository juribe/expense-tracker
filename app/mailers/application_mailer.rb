class ApplicationMailer < ActionMailer::Base
  helper :mailer
  helper_method :greeting_name, :greeting
  layout "mailer"

  def greeting_name(resource)
    MailerHelper.greeting_name(resource)
  end

  def greeting(resource)
    MailerHelper.greeting(resource)
  end
end