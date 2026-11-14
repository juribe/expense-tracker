# frozen_string_literal: true

namespace :yogasto do
  desc "Create or update the Maglev data deletion page"
  task setup_data_deletion: :environment do
    load Rails.root.join("db/seeds/data_deletion.rb")

    site = Maglev::Site.first
    abort("[yogasto:setup_data_deletion] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    LegalDocument::Seeder.new(site: site, data: DataDeletionSeed).call(
      force: ENV["FORCE"] == "1",
      publish: ENV.fetch("PUBLISH", "1") == "1"
    )

    Rails.logger&.info("[yogasto:setup_data_deletion] Data deletion page updated")
  end
end
