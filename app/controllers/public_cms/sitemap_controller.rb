# frozen_string_literal: true

# Public marketing sitemap. Serves both /sitemap.xml and /sitemap (overriding
# Maglev's native sitemap route) so only pages that are actually published
# and indexable reach the XML: never-published draft pages are kept out, while
# Maglev's built-in sitemap only filters by `visible`.
#
# Maglev's I18n context (site locales) is restored around the rendering
# because this controller is plain ActionController::Base.
class PublicCms::SitemapController < ActionController::Base
  protect_from_forgery with: :exception

  PRICING_PATH = "precios"

  def show
    site = Maglev::Site.first
    Maglev::I18n.available_locales = site.locale_prefixes
    @base_url = PublicSiteUrl.base
    Maglev::I18n.with_locale(site.default_locale_prefix) do
      @entries = page_entries + [ pricing_entry ]
      render_layout_free
    end
  end

  private

  def page_entries
    Maglev::Page.where(visible: true).where.not(published_at: nil)
                .order(:created_at).includes(:canonical_paths)
                .reject { |page| page.meta_robots.to_s.downcase.include?("noindex") }
                .map do |page|
      {
        loc: page.index? ? "#{@base_url}/" : "#{@base_url}/#{page.path}",
        lastmod: page.published_at
      }
    end
  end

  # The pricing page is served by the host application (Payment Engine), not by
  # Maglev, so it is appended explicitly to keep it discoverable.
  def pricing_entry
    {
      loc: "#{@base_url}/#{PRICING_PATH}",
      lastmod: pricing_last_modified
    }
  end

  def pricing_last_modified
    timestamps = [
      PaymentEngine::PaymentOption.maximum(:updated_at),
      File.mtime(Rails.root.join("app/views/home/pricing.html.erb"))
    ].compact
    timestamps.max || Time.current
  rescue StandardError
    Time.current
  end

  def render_layout_free
    render "public_cms/sitemap/show", formats: [ :xml ], layout: false
  end
end
