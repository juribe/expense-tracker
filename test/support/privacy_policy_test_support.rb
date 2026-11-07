# frozen_string_literal: true

# Loads the privacy seed data once per process for integration and service tests.
module PrivacyPolicyTestSupport
  def privacy_seed_data
    PrivacyPolicySeed
  rescue NameError
    load Rails.root.join("db/seeds/privacy_policy.rb")
    PrivacyPolicySeed
  end
end
