# frozen_string_literal: true

PaymentEngine.configure do |config|
  config.admin_authentication = lambda do |controller|
    controller.authenticate_user!
  end

  config.admin_authorization = lambda do |controller|
    controller.current_user&.admin?
  end

  config.current_user = lambda do |controller|
    controller.current_user
  end
end
