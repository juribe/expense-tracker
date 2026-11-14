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

  desc "Add the data deletion link to the site footer without replacing editor content"
  task link_data_deletion_in_footer: :environment do
    site = Maglev::Site.first
    abort("[yogasto:link_data_deletion_in_footer] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    result = CmsPage::FooterLink.new(
      site: site,
      label: "Eliminación de datos",
      href: "/eliminacion-de-datos"
    ).call

    Rails.logger&.info("[yogasto:link_data_deletion_in_footer] Footer link #{result}")
  end
end
