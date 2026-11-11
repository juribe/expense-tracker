# frozen_string_literal: true

require "test_helper"

# The sidebar groups pages by domain. Reports used to live inside the
# "Análisis" section as a collapsible submenu; they now have their own
# "Informes" section. These tests pin that structure so the groups do not
# drift back into a single section.
class SidebarNavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Sidebar User",
      email: "sidebar_navigation@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "reports have their own Informes section" do
    get dashboard_path

    assert_response :success
    assert_equal report_paths, section_links("Informes")
  end

  test "Analisis keeps insights and drops the reports submenu" do
    get dashboard_path

    assert_response :success
    assert_equal analysis_paths, section_links("Análisis")
  end

  test "sidebar only uses icons available in the bundled Tabler font" do
    get dashboard_path

    assert_response :success
    theme = Rails.root.join("app/assets/vendor/themes/spike.css").read
    icons = css_select("#sidebarnav i.ti").filter_map do |node|
      node["class"].split.find { |css_class| css_class.start_with?("ti-") }
    end

    missing = icons.uniq.reject { |icon| theme.include?(".#{icon}:before") }

    assert_empty missing, "Sidebar icons missing from the bundled Tabler font: #{missing.join(', ')}"
  end

  private

  def report_paths
    [
      reports_overview_path,
      reports_available_cycle_path,
      reports_savings_capacity_path,
      reports_by_category_path,
      reports_trends_path,
      reports_budgets_path,
      reports_money_sources_path,
      reports_insights_path,
      monthly_reports_path
    ]
  end

  def analysis_paths
    [
      financial_chat_path,
      debt_capacity_path,
      savings_opportunities_path,
      financial_habits_path,
      category_insights_path
    ]
  end

  def section_links(header_text)
    header = css_select("#sidebarnav > li.nav-small-cap").find do |node|
      node.text.strip == header_text
    end
    assert header, "Expected a #{header_text.inspect} sidebar section"

    links = []
    node = header.next_element
    while node && !node.matches?("li.nav-small-cap")
      link = node.at_css("a.sidebar-link")
      links << link["href"] if link
      node = node.next_element
    end
    links
  end
end
