# frozen_string_literal: true

# Loads the legal document seed data once per process for integration and
# service tests.
module PrivacyPolicyTestSupport
  def privacy_seed_data
    PrivacyPolicySeed
  rescue NameError
    load Rails.root.join("db/seeds/privacy_policy.rb")
    PrivacyPolicySeed
  end

  def terms_seed_data
    TermsAndConditionsSeed
  rescue NameError
    load Rails.root.join("db/seeds/terms_and_conditions.rb")
    TermsAndConditionsSeed
  end

  def data_deletion_seed_data
    DataDeletionSeed
  rescue NameError
    load Rails.root.join("db/seeds/data_deletion.rb")
    DataDeletionSeed
  end
end
