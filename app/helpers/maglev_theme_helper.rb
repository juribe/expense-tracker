# MaglevThemeHelper
# Public CMS URLs, canonical tags and alternate language links rendered
# server-side by the Maglev theme layout.
#
# Example: canonical_and_og_url_tags(maglev_page)
module MaglevThemeHelper
  # Canonical origin shared by metadata, JSON-LD and the sitemap.
  def public_cms_base_url
    PublicSiteUrl.base
  end

  # Absolute HTTPS URL for a CMS path. Paths are stored without a leading
  # slash; the home page ("index") resolves to the origin root.
  def public_cms_absolute_url(path)
    normalized = path.to_s.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
    return "#{public_cms_base_url}/" if normalized.blank? || normalized == "index"

    "#{public_cms_base_url}/#{normalized}"
  end

  # Splits a Maglev text setting into non-empty lines.
  def public_cms_text_lines(value)
    value.to_s.lines.map(&:strip).reject(&:blank?)
  end

  # Canonical URL of a CMS page: the explicit canonical_url when the editor
  # set one, otherwise the canonical host plus the page path.
  def public_cms_canonical_url(page)
    page.canonical_url.presence || public_cms_absolute_url(page.index? ? "index" : page.path)
  end

  def normalized_cms_path(page)
    page.index? ? "/" : "/#{page.path}"
  end

  # Renders the canonical link and og:url tags for a CMS page.
  def canonical_and_og_url_tags(page)
    url = public_cms_canonical_url(page)
    safe_join([
      tag.link(rel: "canonical", href: url),
      tag.meta(property: "og:url", content: url),
      tag.meta(name: "twitter:card", content: "summary_large_image"),
      tag.meta(name: "twitter:title", content: page.og_title.presence || page.seo_title),
      tag.meta(name: "twitter:description", content: page.og_description.presence || page.meta_description)
    ].compact, "\n")
  end
end
