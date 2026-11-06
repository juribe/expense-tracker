# frozen_string_literal: true

# Public marketing sitemap. Serves both /sitemap.xml and /sitemap (overriding
# Maglev's native sitemap route) so only pages that are actually published
# and visible reach the XML: never-published draft pages are kept out, while
# Maglev's built-in sitemap only filters by `visible`.
#
# Maglev's I18n context (site locales) is restored around the rendering
# because this controller is plain ActionController::Base.
class PublicCms::SitemapController < ActionController::Base
  protect_from_forgery with: :exception

  def show
    site = Maglev::Site.first
    Maglev::I18n.available_locales = site.locale_prefixes
    @host = request.base_url
    Maglev::I18n.with_locale(site.default_locale_prefix) do
      @pages = Maglev::Page.where(visible: true).where.not(published_at: nil).order(:created_at).includes(:canonical_paths)
      render_layout_free
    end
  end

  private

  def render_layout_free
    render "public_cms/sitemap/show", formats: [:xml], layout: false
  end
end
