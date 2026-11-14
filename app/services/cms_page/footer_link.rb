# CmsPage::FooterLink
# Adds a link to the site-scoped Maglev footer without replacing editor content.
# Republishing one page refreshes the published footer shared by every page.
#
# Example: CmsPage::FooterLink.new(site:, label: "Eliminación de datos", href: "/eliminacion-de-datos").call
module CmsPage
  class FooterLink
    COLUMN_TITLE = "Confianza y legal"
    REFERENCE_HREF = "/privacidad"

    def initialize(site:, label:, href:)
      @site = site
      @label = label
      @href = href
    end

    def call
      Maglev::I18n.with_locale(site.default_locale_prefix) do
        ActiveRecord::Base.transaction do
          footer = site.find_section("footer")
          return :missing_footer if footer.nil?

          blocks = footer["blocks"] ||= []
          existing = blocks.find { |block| link_href(block) == href }

          result = if existing
            :present
          else
            column = column_for(blocks)
            blocks.insert(insertion_index(blocks, column), new_link_block(column))
            site.sections_translations_will_change!
            site.save!
            :created
          end

          publish
          result
        end
      end
    end

    private

    attr_reader :site, :label, :href

    def column_for(blocks)
      blocks.find { |block| column_title(block) == COLUMN_TITLE } ||
        blocks.select { |block| block["type"] == "column" }.last ||
        add_column(blocks)
    end

    def add_column(blocks)
      column = {
        "id" => block_id,
        "type" => "column",
        "settings" => [ { "id" => "title", "value" => COLUMN_TITLE } ]
      }
      blocks.push(column)
      column
    end

    def insertion_index(blocks, column)
      children = blocks.select { |block| block["parent_id"] == column["id"] }
      reference = children.find { |block| link_href(block) == REFERENCE_HREF } || children.last
      (reference ? blocks.index(reference) : blocks.index(column)) + 1
    end

    def new_link_block(column)
      {
        "id" => block_id,
        "type" => "link",
        "settings" => [
          { "id" => "label", "value" => label },
          {
            "id" => "link",
            "value" => {
              "href" => href,
              "text" => label,
              "link_type" => "url",
              "open_new_window" => false
            }
          }
        ],
        "parent_id" => column["id"]
      }
    end

    def link_href(block)
      return unless block["type"] == "link"

      value = Array(block["settings"]).find { |setting| setting["id"] == "link" }&.fetch("value", nil)
      value&.with_indifferent_access&.fetch(:href, nil)
    end

    def column_title(block)
      return unless block["type"] == "column"

      Array(block["settings"]).find { |setting| setting["id"] == "title" }&.fetch("value", nil)
    end

    def publish
      page = Maglev::Page.by_path("eliminacion-de-datos").first ||
             Maglev::Page.by_path("index").first
      Maglev::PublishService.call(site: site, page: page) if page
    end

    def block_id
      SecureRandom.urlsafe_base64(8)
    end
  end
end
