# frozen_string_literal: true

# Builds a minimal Maglev site (published home page) for public CMS tests.
# The theme ships the Home page sections, so the generated content matches
# the marketing page served at "/".
#
# Note: the theme is re-read from disk on every seed. Maglev's rendering
# pipeline mutates the theme hash structures in place (deep_transform_keys!,
# see Maglev::PageComponent), so reusing the boot-time cached theme across
# tests loses the tree `children` blocks after the first render.
module PublicCmsTestSupport
  def create_maglev_site!
    Maglev::Page.delete_all
    Maglev::PagePath.delete_all
    Maglev::Site.delete_all

    theme = Maglev::ThemeFilesystemLoader.new(
      ->(theme:, section:, absolute: true) { "theme/#{section.category}/#{section.id}.jpg" }
    ).call(Rails.root.join("app/theme"))

    site = Maglev::Site.create!(name: "Yogasto", locales: [{ label: "Español", prefix: "es" }])
    Maglev::I18n.available_locales = site.locale_prefixes
    Maglev::I18n.with_locale(site.default_locale_prefix) do
      Maglev::SetupPages.call(site: site, theme: theme)
      Maglev::Page.all.find_each { |page| Maglev::PublishService.call(site: site, page: page) }
    end
    site.reload
  end

  def add_maglev_page(attributes)
    Maglev::I18n.with_locale("es") do
      Maglev::CreatePageService.call(site: Maglev::Site.first, attributes: attributes)
    end
  end
end
