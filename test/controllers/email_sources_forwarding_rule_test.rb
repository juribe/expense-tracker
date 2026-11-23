# frozen_string_literal: true

require "test_helper"

class EmailSourcesForwardingRuleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "simple mode shows a two-step provider-neutral forwarding wizard" do
    user = simple_user
    user.email_sources.create!(
      source_type: "forwarding",
      email: "notifications@bank.com",
      status: "active"
    )
    sign_in user

    get email_sources_path

    assert_response :success
    assert_select "[data-testid=forwarding-rule-card]"
    assert_select ".es-layout [data-testid=forwarding-rule-card]"
    assert_select ".es-layout .es-side [data-testid=forwarding-rule-card]"
    assert_select ".es-side [data-testid=forwarding-rule-card] + .es-howto"
    assert_select "[data-testid=open-forwarding-rule-wizard][data-bs-target='#forwarding-rule-wizard']"
    assert_select "[data-testid=forwarding-rule-wizard]"
    assert_select "[data-testid=forwarding-wizard-nav-explain]"
    assert_select "[data-testid=forwarding-wizard-nav-rule]", text: /Configura el reenvío/
    assert_select "[data-testid=forwarding-wizard-nav-rule] .bank-wizard-nav-num", text: "2"
    assert_select "[data-testid=forwarding-wizard-nav-rule].bank-wizard-nav-item-important", count: 0
    assert_select "[data-testid=forwarding-wizard-explain-step]", text: /regla de reenvío/
    assert_select "[data-testid=forwarding-wizard-rule-step][hidden]"
    assert_select "[data-testid=forwarding-wizard-rule-step] .bank-wizard-bank-title", text: "Configura el reenvío"
    assert_select "#forwarding_rule_senders[rows='2']"
    assert_select "#forwarding_rule_provider option[value=gmail]"
    assert_select "#forwarding_rule_provider option[value=outlook]"
    assert_select "#forwarding_rule_provider option[value=yahoo]"
    assert_select "#forwarding_rule_provider option[value=other]"
    assert_select "#forwarding_rule_address[value=?]", user.forwarding_address
    assert_select "#forwarding_rule_summary"
    assert_select "[data-provider-panel=gmail]"
    assert_select "[data-provider-panel=outlook][hidden]"
    assert_select "[data-provider-panel=yahoo][hidden]"
    assert_select "[data-testid=recognition-next-step]", count: 0
  end

  test "advanced mode keeps recognition and links to the bank wizard" do
    user = detailed_user
    user.email_sources.create!(
      source_type: "forwarding",
      email: "notifications@bank.com",
      status: "active"
    )
    sign_in user

    get email_sources_path

    assert_response :success
    assert_select "[data-testid=forwarding-rule-card]", count: 0
    assert_select "[data-testid=recognition-next-step]"
    assert_select "a[href=?]", money_sources_recognition_path(wizard: 1)
  end

  private

  def simple_user
    User.create!(name: "Forwarding Simple", email: "forwarding_simple_#{SecureRandom.hex(4)}@example.com",
                 password: "password123").tap do |user|
      user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
    end
  end

  def detailed_user
    User.create!(name: "Forwarding Advanced", email: "forwarding_advanced_#{SecureRandom.hex(4)}@example.com",
                 password: "password123")
  end
end
