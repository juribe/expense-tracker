# frozen_string_literal: true

# The built-in `maglev:publish_site` command publishes pages through
# Maglev::PublishService without restoring the site's Maglev locale context.
# That context is required for the title presence validation when the site's
# default locale is not English (Yogasto runs the public site in Spanish).
# This task wraps the service with the proper context so it can be used in
# production right after `maglev:create_site`.
namespace :yogasto do
  desc "Create the Maglev site when missing and publish all its pages"
  task create_cms_site: :environment do
    if Maglev::Site.none?
      Maglev::GenerateSite.call(theme: Maglev.local_themes.first)
      Rails.logger&.info("[yogasto:create_cms_site] Maglev site created")
    end

    Rake::Task["yogasto:publish_cms"].invoke
  end

  desc "Publish every Maglev CMS page (useful idempotently: drafts get a new published snapshot)"
  task publish_cms: :environment do
    site = Maglev::Site.first
    abort("[yogasto:publish_cms] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    Maglev::I18n.with_locale(site.default_locale_prefix) do
      Maglev::Page.all.find_each { |page| Maglev::PublishService.call(site: site, page: page) }
    end

    Rails.logger&.info("[yogasto:publish_cms] All Maglev pages published")
  end

  desc "Create the Maglev pages defined in the theme that do not exist yet"
  task sync_cms_pages: :environment do
    site = Maglev::Site.first
    abort("[yogasto:sync_cms_pages] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    Maglev::I18n.with_locale(site.default_locale_prefix) do
      theme = Maglev::ThemeFilesystemLoader.new(
        ->(theme:, section:, absolute: true) { "theme/#{section.category}/#{section.id}.jpg" }
      ).call(Rails.root.join("app/theme"))

      existing_paths = Maglev::PagePath.where(locale: site.default_locale_prefix).pluck(:value)

      # Only send the missing pages to SetupPages. Reusing the same theme would
      # create duplicates for the pages that already exist.
      theme.pages = theme.pages.reject { |page| existing_paths.include?(page["path"].to_s) }

      if theme.pages.empty?
        Rails.logger&.info("[yogasto:sync_cms_pages] No missing Maglev pages")
      else
        new_pages = Maglev::SetupPages.call(site: site, theme: theme)
        new_pages.each { |page| Maglev::PublishService.call(site: site, page: page) }
        Rails.logger&.info("[yogasto:sync_cms_pages] Created #{new_pages.size} Maglev page(s)")
      end
    end
  end
end
