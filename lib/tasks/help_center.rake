# frozen_string_literal: true

namespace :yogasto do
  desc "Create the initial help center categories and articles as Maglev pages"
  task seed_help_center: :environment do
    load Rails.root.join("db/seeds/help_center.rb")

    site = Maglev::Site.first
    abort("[yogasto:seed_help_center] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    HelpCenter::Seeder.new(site: site, data: HelpCenterSeed).call

    Rails.logger&.info("[yogasto:seed_help_center] Help center content created")
  end

  desc "Publish the PSE payment help article when it is still a draft"
  task publish_help_center_pse: :environment do
    load Rails.root.join("db/seeds/help_center.rb")

    site = Maglev::Site.first
    abort("[yogasto:publish_help_center_pse] No Maglev site exists yet") if site.nil?

    path = "ayuda/membresia-y-pagos/pagar-con-pse"
    Maglev::I18n.available_locales = site.locale_prefixes
    Maglev::I18n.with_locale(site.default_locale_prefix) do
      page = Maglev::Page.by_path(path).first
      if page&.published?
        Rails.logger&.info("[yogasto:publish_help_center_pse] Article already published")
      else
        HelpCenter::Seeder.new(site: site, data: HelpCenterSeed).publish_article(path)
      end
    end
  end

  desc "Add the help center link and retire the legacy /help page"
  task sync_help_center_navigation: :environment do
    site = Maglev::Site.first
    abort("[yogasto:sync_help_center_navigation] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    HelpCenter::NavigationSync.new(site: site).call

    Rails.logger&.info("[yogasto:sync_help_center_navigation] Navigation updated")
  end

  desc "Rebuild the help center read model from published Maglev pages"
  task reindex_help_center: :environment do
    site = Maglev::Site.first
    abort("[yogasto:reindex_help_center] No Maglev site exists yet") if site.nil?

    locale = site.default_locale_prefix
    Maglev::I18n.available_locales = site.locale_prefixes
    Maglev::I18n.with_locale(locale) do
      paths = Maglev::PagePath.where(locale: locale, canonical: true)
                              .where("value = ? OR value LIKE ?", "ayuda", "ayuda/%")
      paths.find_each { |path| HelpCenter::Indexer.new(path.page).call }
    end

    Rails.logger&.info("[yogasto:reindex_help_center] Help center read model rebuilt")
  end

  desc "Prepare the full help center: CMS page, initial content and navigation"
  task setup_help_center: :environment do
    Rake::Task["yogasto:sync_cms_pages"].invoke
    Rake::Task["yogasto:seed_help_center"].invoke
    Rake::Task["yogasto:sync_help_center_navigation"].invoke
    Rake::Task["yogasto:reindex_help_center"].invoke
  end
end
