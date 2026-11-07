# LegalDocument::LinkSync
# Updates shared navigation links from a legacy legal path to its new path,
# retires the legacy page and publishes the site sections.
module LegalDocument
  class LinkSync
    def initialize(site:, legacy_path:, new_path:)
      @site = site
      @legacy_path = legacy_path
      @new_path = new_path
    end

    def call
      Maglev::I18n.with_locale(@site.default_locale_prefix) do
        ActiveRecord::Base.transaction do
          sections = @site.sections || []
          replace_links(sections)
          @site.sections = sections
          @site.save!

          update_contact_page_links
          retire_legacy_page
          publish_site
        end
      end
    end

    private

    def legacy_href
      "/#{@legacy_path}"
    end

    def new_href
      "/#{@new_path}"
    end

    def replace_links(node)
      case node
      when Hash
        node["href"] = new_href if node["href"] == legacy_href
        node.each_value { |value| replace_links(value) }
      when Array
        node.each { |value| replace_links(value) }
      end
    end

    def update_contact_page_links
      page = Maglev::Page.by_path("contact").first
      return if page.nil?

      sections = page.sections || []
      replace_links(sections)
      page.update!(sections: sections)
      Maglev::PublishService.call(site: @site, page: page)
    end

    def retire_legacy_page
      page = Maglev::Page.by_path(@legacy_path).first
      page&.update!(visible: false)
    end

    def publish_site
      page = Maglev::Page.by_path(@new_path).first || Maglev::Page.by_path("index").first
      Maglev::PublishService.call(site: @site, page: page) if page
    end
  end
end
