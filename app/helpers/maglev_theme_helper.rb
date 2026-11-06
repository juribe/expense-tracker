# Helper shared by the Maglev theme (public CMS pages) to render SEO metadata
# server-side. Only available to Maglev controllers because public pages are
# rendered through engine controllers that inherit ApplicationController.
module MaglevThemeHelper
  # Canonical URL of a CMS page: the explicit canonical_url when the editor
  # set one, otherwise the requested URL (the query part is not desirable for
  # canonical URLs, so we rebuild it from base_url + path).
  def public_cms_canonical_url(page)
    page.canonical_url.presence || (request.base_url + normalized_cms_path(page))
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
