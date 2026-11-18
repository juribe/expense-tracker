# frozen_string_literal: true

# Creates a Maglev site with the real help center catalog and applies the SEO
# content seeder, so service and integration tests share the same setup.
module SeoContentTestSupport
  include PublicCmsTestSupport

  def prepare_seo_site!
    @site = create_maglev_site!
    load_seed_file("db/seeds/help_center.rb") unless defined?(HelpCenterSeed)
    load_seed_file("db/seeds/seo_content.rb") unless defined?(SeoContentSeed)
    HelpCenter::Seeder.new(site: @site, data: HelpCenterSeed).call
  end

  def run_seo_seeder!
    CmsPage::SeoContentSeeder.new(site: @site, data: SeoContentSeed).call
  end

  def page_at(path)
    Maglev::I18n.with_locale(HelpCenter::LOCALE) { Maglev::Page.by_path(path).first }
  end

  def page_text(page)
    page.sections.flat_map { |section| Array(section["blocks"]) }
        .flat_map { |block| Array(block["settings"]).map { |setting| setting["value"].to_s } }
        .join(" ")
  end

  private

  def load_seed_file(path)
    load Rails.root.join(path)
  end
end
