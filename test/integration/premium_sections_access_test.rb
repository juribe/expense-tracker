# frozen_string_literal: true

require "test_helper"

# PremiumSectionsAccessTest
# Commercial gating for the sidebar's Análisis and Automatización sections.
# Every controller in both sections declares `require_premium`; the shared
# behavior lives in PremiumAccessTestHelper so each page needs one line.
class PremiumSectionsAccessTest < ActionDispatch::IntegrationTest
  include PremiumAccessTestHelper

  # Análisis
  should_require_premium("financial chat") { get financial_chat_path }
  should_require_premium("debt capacity") { get debt_capacity_path }
  should_require_premium("financial habits") { get financial_habits_path }
  should_require_premium("category insights") { get category_insights_path }

  # Automatización
  should_require_premium("transaction rules") { get transaction_rules_path }
  should_require_premium("gmail connection") { get gmail_connection_path }
  should_require_premium("whatsapp connection") { get whatsapp_settings_path }
  should_require_premium("email sources") { get email_sources_path }
  should_require_premium("mcp tokens") { get mcp_settings_path }
  should_require_premium("source recognition") { get money_sources_recognition_path }

  # Source recognition shares MoneySourcesController with the free money and
  # debt pages, so its three actions carry the gate individually.
  should_require_premium("source recognition update") do
    patch money_source_recognition_path(payment_source), params: { keywords: [ "netflix" ] }
  end
  should_require_premium("source recognition removal") do
    delete money_source_recognition_destroy_path(payment_source)
  end

  # Análisis
  should_allow_premium("financial chat") { get financial_chat_path }
  should_allow_premium("debt capacity") { get debt_capacity_path }
  should_allow_premium("financial habits") { get financial_habits_path }
  should_allow_premium("category insights") { get category_insights_path }

  # Automatización
  should_allow_premium("transaction rules") { get transaction_rules_path }
  should_allow_premium("gmail connection") { get gmail_connection_path }
  should_allow_premium("whatsapp connection") { get whatsapp_settings_path }
  should_allow_premium("email sources") { get email_sources_path }
  should_allow_premium("mcp tokens") { get mcp_settings_path }
  should_allow_premium("source recognition") { get money_sources_recognition_path }

  test "free users keep the money and debt pages served by MoneySourcesController" do
    PaymentEngine::Setting.current.update!(paid_access_required: true)
    revoke_premium(premium_test_user)
    sign_in premium_test_user

    [ money_sources_cash_path, money_sources_pockets_path,
      money_sources_credit_cards_path, money_sources_loans_path ].each do |path|
      get path
      assert_response :success
    end
  end

  private

  def payment_source
    @payment_source ||= premium_test_user.money_sources.create!(
      name: "Cuenta premium", kind: "account", starting_balance: 0
    )
  end
end
