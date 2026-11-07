# PrivacyHelper
# Presentation helpers for the Maglev privacy policy document.
#
# Example: privacy_anchor(section_block)
module PrivacyHelper
  LEGAL_DOCUMENT_PATHS = %w[privacidad terminos-y-condiciones].freeze

  def legal_document_page?(page)
    LEGAL_DOCUMENT_PATHS.include?(page.path)
  end

  PRIVACY_TAGS = %w[
    p br strong em b i u a ul ol li h2 h3 h4 blockquote code pre
    table thead tbody tr th td hr span
  ].freeze
  PRIVACY_ATTRIBUTES = %w[href title target rel].freeze

  def privacy_anchor(block)
    explicit = block.settings.anchor.to_s.strip
    return explicit if explicit.present?

    block.settings.title.to_s.parameterize.presence || "seccion"
  end

  def privacy_nav_label(block)
    block.settings.nav_label.presence || block.settings.title
  end

  def privacy_sanitize_html(value)
    sanitize(value.to_s, tags: PRIVACY_TAGS, attributes: PRIVACY_ATTRIBUTES)
  end

  def privacy_sanitize_inline(value)
    sanitize(value.to_s, tags: %w[br strong em b i u a], attributes: %w[href title target rel])
  end

  def privacy_external_url(value)
    uri = URI.parse(value.to_s)
    uri if %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    nil
  end
end
