# frozen_string_literal: true

require "test_helper"

class BankSetupWizardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Wizard Controller User",
      email: "bank_wizard_ctrl_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    sign_in @user
  end

  test "the recognition page keeps the manual configuration and opens the wizard from its own action" do
    source = create_source(name: "Cuenta Davibank", bank: "Davibank")

    get money_sources_recognition_path

    assert_response :success
    assert_select "a[data-testid='bank-wizard-open'][href='#{money_sources_recognition_path(wizard: 1)}']",
                  text: /#{I18n.t('money_sources.recognition.wizard.open')}/
    # The existing manual controls are untouched.
    assert_select "[data-testid='recognition-help-btn']"
    assert_select "a[data-testid='recognition-bank-edit'][href='#{money_sources_recognition_path(bank_edit: 'legacy:davibank')}']"
    assert_select "a[data-testid='edit-recognition'][href='#{money_sources_recognition_path(edit: source.id)}']"
    # The wizard is only rendered when explicitly opened.
    assert_select "#bank-setup-wizard", count: 0
  end

  test "GET recognition with the wizard renders the supported banks and both guidance sections" do
    davibank = create_source(name: "Cuenta Davibank", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(
      sender: [ "notificaciones@davibank.com" ],
      subject: [ "Compra aprobada" ]
    )
    create_source(name: "Ahorros Bancolombia", bank: "Bancolombia")
    create_source(name: "Efectivo", kind: "cash", bank: "")

    get money_sources_recognition_path(wizard: 1)

    assert_response :success
    assert_select "#bank-setup-wizard[data-bank-wizard]"
    assert_select "[data-testid='bank-wizard-nav-item']", count: 2
    assert_select "[data-testid='bank-wizard-nav-item']", text: /Efectivo/, count: 0
    assert_select "#bank-setup-wizard", text: /#{I18n.t('money_sources.recognition.wizard.title')}/
    assert_select "#bank-setup-wizard", text: /#{I18n.t('money_sources.recognition.wizard.counter', current: 1, total: 2)}/

    assert_select "[data-bank-wizard-panel='legacy:davibank']" do
      assert_select "input[name='senders[]'][value='notificaciones@davibank.com']"
      assert_select "input[name='subjects[]'][value='Compra aprobada']"
      assert_select "input[type='hidden'][name='senders[]'][value='']"
      assert_select "input[type='hidden'][name='subjects[]'][value='']"
      assert_select "[data-testid='bank-wizard-mail-sender']", text: /notificaciones@davibank.com/
      assert_select "[data-testid='bank-wizard-mail-subject']", text: /Compra aprobada/
      assert_select "h4", text: /#{I18n.t('money_sources.recognition.wizard.sender_title')}/
      assert_select "h4", text: /#{I18n.t('money_sources.recognition.wizard.subject_title')}/
    end
    assert_select "[data-bank-wizard-panel='legacy:bancolombia']"
  end

  test "GET recognition with the wizard exposes the existing suggestions per bank" do
    create_source(name: "Cuenta Davibank", bank: "Davibank")
    sibling = create_source(name: "Tarjeta Davibank", kind: "credit_card", bank: "Davibank")
    sibling.ensure_recognition.replace_identifiers(sender: [ "notificaciones@davibank.com" ])

    get money_sources_recognition_path(wizard: 1)

    assert_response :success
    assert_select "[data-bank-wizard-panel='legacy:davibank'] " \
                  ".recognition-chip-suggested[data-suggested-for='senders'][data-suggested-value='notificaciones@davibank.com']"
  end

  test "GET recognition with the wizard includes the separate, unverifiable mail filter step" do
    create_source(name: "Cuenta Davibank", bank: "Davibank")

    get money_sources_recognition_path(wizard: 1)

    assert_response :success
    assert_select "[data-testid='bank-wizard-filter-step']" do
      assert_select "h3", text: I18n.t("money_sources.recognition.wizard.filters_title")
      assert_select "strong", text: I18n.t("money_sources.recognition.wizard.filters_heading")
      assert_select "p", text: I18n.t("money_sources.recognition.wizard.filters_body")
      assert_select "a[href='https://support.google.com/mail/answer/6579?hl=es'][target='_blank'][rel='noopener']"
      assert_select "[data-testid='bank-wizard-filter-unverifiable']",
                    text: I18n.t("money_sources.recognition.wizard.filters_unverifiable")
      assert_select "[data-testid='bank-wizard-filter-limitation']",
                    text: I18n.t("money_sources.recognition.wizard.filters_limitation")
    end
    assert_select "[data-bank-wizard-go='filters']", text: /#{I18n.t('money_sources.recognition.wizard.filters_nav')}/
  end

  test "PATCH recognition as JSON saves bank senders and subjects and reports the bank status" do
    source = create_source(name: "Cuenta Davibank", bank: "Davibank")

    patch money_source_recognition_path(source.id),
          params: {
            senders: [ "notificaciones@davibank.com", "davibank.com" ],
            subjects: [ "Compra aprobada", "From: alertas@davibank.com" ]
          },
          as: :json

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["configured"]

    identifiers = source.reload.recognition.recognition_identifiers
    assert_equal [ "notificaciones@davibank.com" ], identifiers.confirmed.where(kind: "sender").pluck(:value)
    assert_equal [ "davibank.com" ], identifiers.confirmed.where(kind: "domain").pluck(:value)
    assert_equal [ "Compra aprobada" ], identifiers.confirmed.where(kind: "subject").pluck(:value)
    assert_equal [ "From: alertas@davibank.com" ], identifiers.confirmed.where(kind: "header").pluck(:value)
    # The wizard never touches product keywords.
    assert_empty identifiers.confirmed.where(kind: "keyword")
  end

  test "PATCH recognition as JSON does not duplicate repeated values" do
    source = create_source(name: "Cuenta Davibank", bank: "Davibank")
    values = { senders: [ "notificaciones@davibank.com" ], subjects: [ "Compra aprobada" ] }

    2.times { patch money_source_recognition_path(source.id), params: values, as: :json }

    assert_response :success
    identifiers = source.reload.recognition.recognition_identifiers
    assert_equal 1, identifiers.where(kind: "sender", value: "notificaciones@davibank.com").count
    assert_equal 1, identifiers.where(kind: "subject", value: "Compra aprobada").count
  end

  test "PATCH recognition as JSON clears both sections when the wizard submits empty values" do
    source = create_source(name: "Cuenta Davibank", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(sender: [ "notificaciones@davibank.com" ], subject: [ "Compra aprobada" ])

    patch money_source_recognition_path(source.id),
          params: { senders: [ "" ], subjects: [ "" ] },
          as: :json

    assert_response :success
    assert_not JSON.parse(response.body)["configured"]
    assert_nil source.reload.recognition
  end

  test "PATCH recognition as JSON never writes to another user's source" do
    other_user = User.create!(
      name: "Other Wizard User",
      email: "bank_wizard_other_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    foreign = other_user.money_sources.create!(name: "Cuenta ajena", kind: "account", starting_balance: 0)
    foreign.ensure_recognition.replace_identifiers(sender: [ "ajeno@example.com" ])

    patch money_source_recognition_path(foreign.id),
          params: { senders: [ "notificaciones@davibank.com" ], subjects: [ "Compra aprobada" ] },
          as: :json

    assert_response :not_found
    assert_equal [ "ajeno@example.com" ],
                 foreign.reload.recognition.recognition_identifiers.confirmed.where(kind: "sender").pluck(:value)
  end

  private

  def create_source(name:, kind: "account", bank: "Davibank")
    @user.money_sources.create!(name: name, kind: kind, bank: bank, starting_balance: 0)
  end
end
