# PublicSiteUrl
# Canonical HTTPS origin for CMS metadata, JSON-LD and the sitemap.
#
# Example: PublicSiteUrl.base # => "https://yogasto.co"
module PublicSiteUrl
  DEFAULT = "https://yogasto.co"

  module_function

  def base
    configured = Rails.application.config.x.public_site_url
    value = configured.is_a?(String) ? configured.strip : ""
    (value.presence || DEFAULT).sub(%r{/+\z}, "")
  end
end
