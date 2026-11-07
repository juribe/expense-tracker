# frozen_string_literal: true

namespace :yogasto do
  desc "Create or update the Maglev security page from the theme"
  task setup_security_page: :environment do
    site = Maglev::Site.first
    abort("[yogasto:setup_security_page] No Maglev site exists yet") if site.nil?

    theme = Maglev::ThemeFilesystemLoader.new(
      ->(theme:, section:, absolute: true) { "theme/#{section.category}/#{section.id}.jpg" }
    ).call(Rails.root.join("app/theme"))

    page_theme = theme.pages.find { |page| page["path"].to_s == "seguridad" }
    abort("[yogasto:setup_security_page] No existe la página seguridad en el tema") if page_theme.nil?

    Maglev::I18n.available_locales = site.locale_prefixes

    Maglev::I18n.with_locale(site.default_locale_prefix) do
      page = Maglev::Page.by_path("seguridad").first

      if page.nil?
        theme.pages = [ page_theme ]
        page = Maglev::SetupPages.call(site: site, theme: theme).first
      elsif ENV["FORCE"] == "1" || page.sections.none? { |section| section["type"] == "security_process" }
        footer_sections = page.sections.select { |section| section["type"].to_s == "footer" }
        page.sections = page.sections.select { |section| section["type"].to_s == "navbar" }
        page.save!

        page_theme["sections"].each do |section_attributes|
          next if %w[navbar footer].include?(section_attributes["type"].to_s)

          Maglev::Content::AddSectionService.call(
            theme: theme,
            site: site,
            page: page,
            section_type: section_attributes["type"],
            content: section_attributes
          )
        end

        page.sections = page.sections + footer_sections
        page.save!

        page.title = page_theme["title"]
        page.seo_title = page_theme["seo_title"]
        page.meta_description = page_theme["meta_description"]
        page.og_title = page_theme["og_title"]
        page.og_description = page_theme["og_description"]
        page.save!
      end

      Maglev::PublishService.call(site: site, page: page) if ENV.fetch("PUBLISH", "1") == "1"
    end

    if ENV.fetch("PUBLISH", "1") == "1"
      CmsPage::PathSync.new(
        site: site,
        legacy_path: "security",
        new_path: "seguridad"
      ).call
    end

    Rails.logger&.info("[yogasto:setup_security_page] Security page updated")
  end
end
