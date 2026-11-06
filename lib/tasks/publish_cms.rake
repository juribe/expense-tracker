# frozen_string_literal: true

# The built-in `maglev:publish_site` command publishes pages through
# Maglev::PublishService without restoring the site's Maglev locale context.
# That context is required for the title presence validation when the site's
# default locale is not English (Yogasto runs the public site in Spanish).
# This task wraps the service with the proper context so it can be used in
# production right after `maglev:create_site`.
namespace :yogasto do
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
end
