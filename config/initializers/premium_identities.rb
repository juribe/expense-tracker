# frozen_string_literal: true

# Extends the payment engine access questions with the premium identity
# history: an account whose email identity already used premium keeps the free
# plan and cannot obtain premium again.
Rails.application.config.to_prepare do
  PaymentEngine::UserAccess.prepend(PremiumIdentities::UserAccessExtension)
end
