# frozen_string_literal: true

require "test_helper"

# Adds the data deletion link to the site-scoped Maglev footer and refreshes
# the published footer shared by every public page.
class PublicCmsFooterLinkTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport

  setup do
    @site = create_maglev_site!
    remove_data_deletion_link
  end

  test "agrega el enlace al footer del sitio y lo publica" do
    result = link_footer

    assert_equal :created, result
    assert_equal 1, footer_links.count { |block| link_href(block) == "/eliminacion-de-datos" }
    assert_equal "Eliminación de datos", link_label(deletion_link)

    get "https://yogasto.co/"

    assert_response :success
    assert_select "footer.site-footer a[href='/eliminacion-de-datos']", count: 1
    assert_select "footer.site-footer a[href='/privacidad']", count: 1
  end

  test "es idempotente y no duplica el enlace" do
    2.times { link_footer }

    assert_equal 1, footer_links.count { |block| link_href(block) == "/eliminacion-de-datos" }

    get "https://yogasto.co/"

    assert_select "footer.site-footer a[href='/eliminacion-de-datos']", count: 1
  end

  test "respeta el texto de un enlace existente sin duplicarlo" do
    CmsPage::FooterLink.new(site: @site, label: "Texto anterior", href: "/eliminacion-de-datos").call

    result = link_footer

    assert_equal :present, result
    assert_equal 1, footer_links.count { |block| link_href(block) == "/eliminacion-de-datos" }
    assert_equal "Texto anterior", link_label(deletion_link)
  end

  test "usa la última columna cuando no encuentra la columna esperada" do
    rename_legal_column("Otros enlaces")

    link_footer

    assert_equal last_column["id"], deletion_link["parent_id"]
  end

  test "crea una columna cuando el footer no tiene columnas" do
    @site = replace_footer_blocks([])

    result = link_footer

    assert_equal :created, result
    column = @site.find_section("footer")["blocks"].find { |block| block["type"] == "column" }
    assert_equal "Confianza y legal", column_title(column)
    assert_equal column["id"], deletion_link["parent_id"]
  end

  test "no falla cuando el sitio no tiene footer" do
    remove_footer

    assert_equal :missing_footer, link_footer
  end

  private

  def link_footer
    CmsPage::FooterLink.new(
      site: @site,
      label: "Eliminación de datos",
      href: "/eliminacion-de-datos"
    ).call
  end

  def footer_blocks
    with_locale { @site.reload.find_section("footer").fetch("blocks") }
  end

  def footer_links
    footer_blocks.select { |block| block["type"] == "link" }
  end

  def deletion_link
    footer_links.find { |block| link_href(block) == "/eliminacion-de-datos" }
  end

  def last_column
    footer_blocks.select { |block| block["type"] == "column" }.last
  end

  def link_href(block)
    link_value(block)&.with_indifferent_access&.fetch(:href, nil)
  end

  def link_label(block)
    setting_value(block, "label")
  end

  def column_title(block)
    setting_value(block, "title")
  end

  def link_value(block)
    Array(block["settings"]).find { |setting| setting["id"] == "link" }&.fetch("value", nil)
  end

  def setting_value(block, id)
    Array(block["settings"]).find { |setting| setting["id"] == id }&.fetch("value", nil)
  end

  def rename_legal_column(title)
    update_footer_blocks do |blocks|
      blocks.each do |block|
        next unless block["type"] == "column" && column_title(block) == "Confianza y legal"

        block["settings"].find { |setting| setting["id"] == "title" }["value"] = title
      end
    end
  end

  def replace_footer_blocks(blocks)
    update_footer_blocks { |current| current.replace(blocks) }
  end

  def remove_data_deletion_link
    update_footer_blocks do |blocks|
      blocks.reject! { |block| link_href(block) == "/eliminacion-de-datos" }
    end
  end

  def remove_footer
    with_locale do
      @site.sections_translations_will_change!
      @site.sections = @site.sections.reject { |section| section["type"] == "footer" }
      @site.save!
    end
  end

  def update_footer_blocks
    with_locale do
      blocks = @site.find_section("footer").fetch("blocks")
      yield blocks
      @site.sections_translations_will_change!
      @site.save!
      @site.reload
    end
  end

  def with_locale(&block)
    Maglev::I18n.with_locale(@site.default_locale_prefix, &block)
  end
end
