# HelpCenter::NavigationSync
# Keeps the help center link out of the shared header, updates legacy /help
# links and retires the old minimal help page. The footer remains the entry point.
class HelpCenter::NavigationSync
  HELP_LABEL = "Centro de ayuda"
  HELP_PATH = "/ayuda"

  def initialize(site:)
    @site = site
  end

  def call
    Maglev::I18n.with_locale(@site.default_locale_prefix) do
      ActiveRecord::Base.transaction do
        sections = @site.sections || []
        remove_navbar_link(sections)
        replace_help_links(sections)
        @site.sections = sections
        @site.save!

        retire_legacy_page
        publish_site
      end
    end
  end

  private

  def remove_navbar_link(sections)
    navbar = sections.find { |section| section["type"] == "navbar" }
    return if navbar.nil?

    navbar["blocks"] = (navbar["blocks"] || []).reject do |block|
      block["type"] == "link" && label_of(block) == HELP_LABEL
    end
  end

  def label_of(block)
    block["settings"]&.find { |setting| setting["id"] == "label" }&.dig("value")
  end

  def replace_help_links(node)
    case node
    when Hash
      node["href"] = HELP_PATH if node["href"] == "/help"
      node.each_value { |value| replace_help_links(value) }
    when Array
      node.each { |value| replace_help_links(value) }
    end
  end

  def retire_legacy_page
    page = Maglev::Page.by_path("help").first
    page&.update!(visible: false)
  end

  def publish_site
    page = Maglev::Page.by_path("ayuda").first || Maglev::Page.by_path("index").first
    Maglev::PublishService.call(site: @site, page: page) if page
  end
end
