# frozen_string_literal: true

namespace :yogasto do
  desc "Create or update the Maglev privacy policy page"
  task setup_privacy_policy: :environment do
    load Rails.root.join("db/seeds/privacy_policy.rb")

    site = Maglev::Site.first
    abort("[yogasto:setup_privacy_policy] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    PrivacyPolicy::Seeder.new(site: site, data: PrivacyPolicySeed).call(
      force: ENV["FORCE"] == "1",
      publish: ENV.fetch("PUBLISH", "1") == "1"
    )
    PrivacyPolicy::LinkSync.new(site: site).call if ENV.fetch("PUBLISH", "1") == "1"

    Rails.logger&.info("[yogasto:setup_privacy_policy] Privacy policy updated")
  end
end
