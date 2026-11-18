# frozen_string_literal: true

namespace :yogasto do
  desc "Create/update the SEO content catalog, landing pages and internal links"
  task setup_seo_content: :environment do
    load Rails.root.join("db/seeds/seo_content.rb")

    site = Maglev::Site.first
    abort("[yogasto:setup_seo_content] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    CmsPage::SeoContentSeeder.new(site: site, data: SeoContentSeed).call

    Rails.logger&.info("[yogasto:setup_seo_content] SEO content updated")
  end

  desc "Apply the public CMS content safely after a deployment"
  task deploy_cms_content: :environment do
    site = Maglev::Site.first

    if site.nil?
      Rake::Task["yogasto:create_cms_site"].invoke
    else
      Rake::Task["yogasto:sync_cms_pages"].invoke
    end

    site = Maglev::Site.first
    abort("[yogasto:deploy_cms_content] No Maglev site exists yet") if site.nil?

    Maglev::I18n.available_locales = site.locale_prefixes
    help_seeded = Maglev::I18n.with_locale(site.default_locale_prefix) do
      Maglev::Page.by_path("ayuda/primeros-pasos/que-es-yogasto").exists?
    end

    Rake::Task["yogasto:setup_help_center"].invoke unless help_seeded
    Rake::Task["yogasto:setup_seo_content"].invoke
    Rake::Task["yogasto:reindex_help_center"].invoke

    Rails.logger&.info("[yogasto:deploy_cms_content] Public CMS content applied")
  end
end
