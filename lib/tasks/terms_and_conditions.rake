# frozen_string_literal: true

namespace :yogasto do
  desc "Create or update the Maglev terms and conditions page"
  task setup_terms_and_conditions: :environment do
    load Rails.root.join("db/seeds/terms_and_conditions.rb")

    site = Maglev::Site.first
    abort("[yogasto:setup_terms_and_conditions] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    LegalDocument::Seeder.new(site: site, data: TermsAndConditionsSeed).call(
      force: ENV["FORCE"] == "1",
      publish: ENV.fetch("PUBLISH", "1") == "1"
    )
    if ENV.fetch("PUBLISH", "1") == "1"
      CmsPage::PathSync.new(
        site: site,
        legacy_path: "terms",
        new_path: "terminos-y-condiciones"
      ).call
    end

    Rails.logger&.info("[yogasto:setup_terms_and_conditions] Terms and conditions updated")
  end
end
