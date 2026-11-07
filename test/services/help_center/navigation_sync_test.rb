# frozen_string_literal: true

require "test_helper"

class HelpCenterNavigationSyncTest < ActiveSupport::TestCase
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    @site = create_maglev_site!
  end

  test "retira el enlace del navbar, lo mantiene en el footer y actualiza enlaces antiguos" do
    add_help_link_to_navbar!
    point_help_link_to_legacy_path!

    HelpCenter::NavigationSync.new(site: @site).call

    assert_nil help_navbar_block
    assert_equal "/ayuda", footer_help_link.dig("value", "href")

    published = Maglev::SectionsContentStore.published.find_by(container: @site)
    published_sections = published.sections_translations["es"]
    published_navbar = published_sections.find { |s| s["type"] == "navbar" }
    published_footer = published_sections.find { |s| s["type"] == "footer" }

    labels = published_navbar["blocks"].filter_map do |block|
      block["settings"]&.find { |setting| setting["id"] == "label" }&.dig("value")
    end
    refute_includes labels, "Centro de ayuda"
    assert_includes link_hrefs(published_footer), "/ayuda"
  end

  test "oculta la página antigua /help" do
    updated = {}
    legacy = Object.new
    legacy.define_singleton_method(:update!) { |**attrs| updated.merge!(attrs) }

    original = Maglev::Page.method(:by_path)
    stub_method(Maglev::Page, :by_path, ->(path) { path == "help" ? [ legacy ] : original.call(path) }) do
      HelpCenter::NavigationSync.new(site: @site).call
    end

    assert_equal({ visible: false }, updated)
  end

  private

  def add_help_link_to_navbar!
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      sections = @site.sections
      navbar = sections.find { |section| section["type"] == "navbar" }
      blocks = navbar["blocks"] ||= []
      insert_index = blocks.index { |block| block["type"] == "login" } || blocks.length
      blocks.insert(insert_index, help_link_block)
      @site.sections = sections
      @site.save!
    end
  end

  def help_link_block
    {
      "id" => SecureRandom.urlsafe_base64(8),
      "type" => "link",
      "settings" => [
        { "id" => "label", "value" => "Centro de ayuda" },
        { "id" => "link", "value" => {
          "link_type" => "url",
          "href" => "/ayuda",
          "open_new_window" => false
        } }
      ]
    }
  end

  def point_help_link_to_legacy_path!
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      sections = @site.sections
      footer = sections.find { |section| section["type"] == "footer" }
      link = footer["blocks"].filter_map do |block|
        block["settings"]&.find { |setting| setting["id"] == "link" }
      end.find { |setting| setting.dig("value", "href") == "/ayuda" }
      link["value"]["href"] = "/help"
      @site.sections = sections
      @site.save!
    end
  end

  def help_navbar_block
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      navbar = @site.sections.find { |section| section["type"] == "navbar" }
      navbar["blocks"].find { |block| label_of(block) == "Centro de ayuda" }
    end
  end

  def footer_help_link
    Maglev::I18n.with_locale(HelpCenter::LOCALE) do
      footer = @site.sections.find { |section| section["type"] == "footer" }
      footer["blocks"].filter_map do |block|
        block["settings"]&.find { |setting| setting["id"] == "link" }
      end.find { |setting| setting.dig("value", "href") == "/ayuda" }
    end
  end

  def link_hrefs(node)
    case node
    when Hash
      own = node["href"] == "/ayuda" ? [ "/ayuda" ] : []
      own + node.values.flat_map { |value| link_hrefs(value) }
    when Array
      node.flat_map { |value| link_hrefs(value) }
    else
      []
    end
  end

  def label_of(block)
    block["settings"]&.find { |setting| setting["id"] == "label" }&.dig("value")
  end
end
