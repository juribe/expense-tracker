# PrivacyPolicy::LinkSync
# Updates shared navigation links from /privacy to /privacidad, retires the
# legacy page and publishes the site sections.
module PrivacyPolicy
  class LinkSync
    def initialize(site:)
      @site = site
    end

    def call
      Maglev::I18n.with_locale(@site.default_locale_prefix) do
        ActiveRecord::Base.transaction do
          sections = @site.sections || []
          replace_privacy_links(sections)
          @site.sections = sections
          @site.save!

          update_contact_page_links
          retire_legacy_page
          publish_site
        end
      end
    end

    private

    def replace_privacy_links(node)
      case node
      when Hash
        node["href"] = "/privacidad" if node["href"] == "/privacy"
        node.each_value { |value| replace_privacy_links(value) }
      when Array
        node.each { |value| replace_privacy_links(value) }
      end
    end

    def update_contact_page_links
      page = Maglev::Page.by_path("contact").first
      return if page.nil?

      sections = page.sections || []
      replace_privacy_links(sections)
      page.update!(sections: sections)
      Maglev::PublishService.call(site: @site, page: page)
    end

    def retire_legacy_page
      page = Maglev::Page.by_path("privacy").first
      page&.update!(visible: false)
    end

    def publish_site
      page = Maglev::Page.by_path("privacidad").first || Maglev::Page.by_path("index").first
      Maglev::PublishService.call(site: @site, page: page) if page
    end
  end
end
