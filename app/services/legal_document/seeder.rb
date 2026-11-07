# LegalDocument::Seeder
# Creates or updates a Maglev legal document page from structured seed data.
# Existing editor content is preserved unless force: true is passed.
#
# Example: LegalDocument::Seeder.new(site: site, data: PrivacyPolicySeed).call
module LegalDocument
  class Seeder
    def initialize(site:, data:)
      @site = site
      @data = data
    end

    def call(force: false, publish: false)
      Maglev::I18n.with_locale(locale) do
        ActiveRecord::Base.transaction do
          page = find_or_create_page
          update_page!(page, force: force)
          publish_page(page) if publish
          page
        end
      end
    end

    private

    attr_reader :site, :data

    def locale
      site.default_locale_prefix
    end

    def find_or_create_page
      Maglev::Page.by_path(data::PAGE[:path]).first ||
        Maglev::CreatePageService.call(site: site, attributes: { title: data::PAGE[:title], path: data::PAGE[:path] })
    end

    def update_page!(page, force:)
      return page if !force && existing_document_blocks?(page)

      page.update!(
        title: data::PAGE[:title],
        seo_title: data::PAGE[:seo_title],
        meta_description: data::PAGE[:meta_description],
        og_title: data::PAGE[:og_title],
        og_description: data::PAGE[:og_description],
        meta_robots: data::PAGE[:meta_robots],
        sections: page_sections
      )
      page
    end

    def existing_document_blocks?(page)
      document = page.sections&.find { |section| section["type"] == "privacy_document" }
      document.present? && document["blocks"].present?
    end

    def page_sections
      [
        section("navbar"),
        section("privacy_document", data::DOCUMENT_SETTINGS, blocks: document_blocks),
        section("footer")
      ]
    end

    def document_blocks
      data::SECTIONS.flat_map { |definition| section_blocks(definition) }
    end

    def section_blocks(definition)
      id = block_id
      root = {
        "id" => id,
        "type" => "privacy_section",
        "settings" => setting_pairs(
          anchor: definition[:anchor],
          title: definition[:title],
          number: definition[:number],
          nav_label: definition[:nav_label],
          intro: definition[:intro]
        ),
        "blocks" => []
      }

      [ root ] + Array(definition[:children]).flat_map { |child| content_blocks(child, parent_id: id) }
    end

    def content_blocks(definition, parent_id:)
      id = block_id
      block = {
        "id" => id,
        "type" => definition[:type],
        "settings" => setting_pairs(block_settings(definition)),
        "blocks" => [],
        "parent_id" => parent_id
      }

      [ block ] + child_blocks(definition, parent_id: id)
    end

    def child_blocks(definition, parent_id:)
      case definition[:type]
      when "privacy_list"
        Array(definition[:items]).map do |item|
          {
            "id" => block_id,
            "type" => "privacy_list_item",
            "settings" => setting_pairs(text: item),
            "blocks" => [],
            "parent_id" => parent_id
          }
        end
      when "privacy_cards"
        Array(definition[:items]).map do |item|
          {
            "id" => block_id,
            "type" => "privacy_card",
            "settings" => setting_pairs(item),
            "blocks" => [],
            "parent_id" => parent_id
          }
        end
      when "privacy_providers"
        Array(definition[:items]).map do |item|
          {
            "id" => block_id,
            "type" => "privacy_provider",
            "settings" => setting_pairs(item),
            "blocks" => [],
            "parent_id" => parent_id
          }
        end
      else
        []
      end
    end

    def block_settings(definition)
      case definition[:type]
      when "privacy_text"
        { text: definition[:text] }
      when "privacy_list"
        { ordered: definition[:ordered] ? "ordered" : "unordered" }
      when "privacy_cards"
        { columns: definition[:columns] }
      when "privacy_callout"
        { variant: definition[:variant], title: definition[:title], text: definition[:text] }
      when "privacy_providers"
        {}
      else
        {}
      end
    end

    def section(type, settings = {}, blocks: [])
      {
        "type" => type,
        "settings" => setting_pairs(settings),
        "blocks" => blocks
      }
    end

    def setting_pairs(settings)
      settings.compact.map { |id, value| { "id" => id.to_s, "value" => value } }
    end

    def block_id
      SecureRandom.urlsafe_base64(8)
    end

    def publish_page(page)
      Maglev::PublishService.call(site: site, page: page)
    end
  end
end
