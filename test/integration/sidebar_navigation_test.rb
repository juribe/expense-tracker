# frozen_string_literal: true

require "test_helper"

# The sidebar groups pages by domain. Reports used to live inside the
# "Análisis" section as a collapsible submenu; they now have their own
# "Informes" section. Every section is a dropdown that starts collapsed
# except the one that owns the current page.
class SidebarNavigationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  SECTION_IDS = %w[
    sidebarSectionHome
    sidebarSectionActivity
    sidebarSectionMoney
    sidebarSectionDebt
    sidebarSectionPlanning
    sidebarSectionReports
    sidebarSectionInsights
    sidebarSectionAutomation
    sidebarSectionSettings
    sidebarSectionAdmin
  ].freeze

  setup do
    # Admin so the admin-only section is rendered and exercised too.
    @user = User.create!(
      name: "Sidebar User",
      email: "sidebar_navigation@example.com",
      password: "password123",
      admin: true
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

  test "every section is a dropdown and only the selected one starts open" do
    get dashboard_path

    assert_response :success
    assert_select "#sidebarnav > li.collapse", count: SECTION_IDS.size
    assert_select "#sidebarnav > li.collapse.show", count: 1
    assert_select "a.nav-section-toggle i.ti-chevron-right", count: SECTION_IDS.size
    assert_select "a.nav-section-toggle .nav-section-icon", count: SECTION_IDS.size
    assert_select "#sidebarSectionHome.show"
    assert_select "#sidebarSectionHome a.sidebar-link[href=?]", dashboard_path
    SECTION_IDS.excluding("sidebarSectionHome").each do |section_id|
      assert_select "##{section_id}.show", count: 0
    end
  end

  test "the dropdown toggle marks the open section expanded" do
    get reports_overview_path

    assert_response :success
    assert_select "a.nav-section-toggle[href='#sidebarSectionReports'][aria-expanded='true']"
    assert_select "a.nav-section-toggle[href='#sidebarSectionHome'][aria-expanded='false']"
    assert_select "#sidebarSectionReports.show"
  end

  test "money sources open the Dinero dropdown while cards and loans open Deudas" do
    get money_sources_cash_path
    assert_select "#sidebarSectionMoney.show"
    assert_select "#sidebarSectionDebt.show", count: 0

    get money_sources_credit_cards_path
    assert_select "#sidebarSectionDebt.show"
    assert_select "#sidebarSectionMoney.show", count: 0
  end

  test "transfers belong to Actividad instead of Informes" do
    get reports_transfers_path

    assert_response :success
    assert_select "#sidebarSectionActivity.show"
    assert_select "#sidebarSectionReports.show", count: 0
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

    header.next_element.css("a.sidebar-link").map { |link| link["href"] }
  end
end
