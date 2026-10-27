# frozen_string_literal: true

require "application_system_test_case"

class BankSetupWizardSystemTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(
      name: "Wizard System User",
      email: "bank_wizard_system_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @user.confirm
    @davibank = create_source(name: "Cuenta Davibank", bank: "Davibank")
    @bancolombia = create_source(name: "Ahorros Bancolombia", bank: "Bancolombia")
    # Banks are listed alphabetically by label on the recognition page.
    @first_key = bank_key(@bancolombia)
    @second_key = bank_key(@davibank)
  end

  test "opens, closes and reopens the wizard without leaving the recognition page" do
    sign_in @user
    visit money_sources_recognition_path

    click_link I18n.t("money_sources.recognition.wizard.open")

    assert_modal_open
    assert_selector "[data-testid='bank-wizard-nav-item']", count: 2

    find("#bank-setup-wizard .btn-close").click
    assert_modal_closed

    click_link I18n.t("money_sources.recognition.wizard.open")
    assert_modal_open
    assert_text I18n.t("money_sources.recognition.wizard.title")
  end

  test "navigates between banks, keeps unsaved edits and saves senders and subjects" do
    sign_in @user
    open_wizard

    within_bank(@first_key) do
      add_chip("senders", "notificaciones@bancolombia.com")
    end

    # Moving to another bank and back keeps the unsaved edit in place.
    find("[data-bank-wizard-go='#{@second_key}']").click
    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
    find("[data-bank-wizard-go='#{@first_key}']").click
    within_bank(@first_key) do
      assert_selector ".recognition-chip", text: /notificaciones@bancolombia.com/
      add_chip("subjects", "Compra aprobada")
    end

    click_button I18n.t("money_sources.recognition.wizard.save_continue")

    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
    assert_equal "Configurado", nav_state(@first_key)

    identifiers = @bancolombia.reload.recognition.recognition_identifiers.confirmed
    assert_equal [ "notificaciones@bancolombia.com" ], identifiers.where(kind: "sender").pluck(:value)
    assert_equal [ "Compra aprobada" ], identifiers.where(kind: "subject").pluck(:value)

    # Editing an earlier bank shows the persisted values again.
    find("[data-bank-wizard-go='#{@first_key}']").click
    within_bank(@first_key) do
      assert_selector "input[name='senders[]'][value='notificaciones@bancolombia.com']", visible: :all
      assert_selector "input[name='subjects[]'][value='Compra aprobada']", visible: :all
    end

    click_button I18n.t("money_sources.recognition.wizard.save_continue") # save bank 1 and advance
    click_button I18n.t("money_sources.recognition.wizard.save_continue") # save bank 2 and advance

    assert_selector "[data-testid='bank-wizard-filter-step'].is-active"
    click_button I18n.t("money_sources.recognition.wizard.finish")

    assert_modal_closed
    assert_current_path money_sources_recognition_path
    assert_text I18n.t("money_sources.recognition.group_configured")
  end

  test "skipping a bank preserves its previous configuration and is not reported as configured" do
    @bancolombia.ensure_recognition.replace_identifiers(sender: [ "notificaciones@bancolombia.com" ])

    sign_in @user
    open_wizard

    click_button I18n.t("money_sources.recognition.wizard.skip")

    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
    assert_equal "Omitido", nav_state(@first_key)
    assert_equal [ "notificaciones@bancolombia.com" ],
                 @bancolombia.reload.recognition.recognition_identifiers.confirmed.where(kind: "sender").pluck(:value)

    find("[data-bank-wizard-go='#{@first_key}']").click
    within_bank(@first_key) do
      assert_selector "input[name='senders[]'][value='notificaciones@bancolombia.com']", visible: :all
      assert_text I18n.t("money_sources.recognition.wizard.state_skipped")
    end

    # Closing and reopening keeps the omission; a full refresh restores it too.
    find("#bank-setup-wizard .btn-close").click
    assert_modal_closed
    click_link I18n.t("money_sources.recognition.wizard.open")
    assert_modal_open
    assert_equal "Omitido", nav_state(@first_key)

    page.refresh
    assert_modal_open
    assert_equal "Omitido", nav_state(@first_key)
  end

  test "accepts a suggestion and removes a chip through the existing controls" do
    @bancolombia.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "sender", value: "notificaciones@bancolombia.com", status: "suggested", origin: "gmail"
    )

    sign_in @user
    open_wizard

    within_bank(@first_key) do
      find(".recognition-chip-suggested[data-suggested-for='senders']" \
           "[data-suggested-value='notificaciones@bancolombia.com'] [data-recognition-accept-suggestion]").click
      assert_selector "input[name='senders[]'][value='notificaciones@bancolombia.com']", visible: :all
    end

    click_button I18n.t("money_sources.recognition.wizard.save_continue")
    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
    assert @bancolombia.reload.recognition.recognition_identifiers.confirmed
                     .exists?(kind: "sender", value: "notificaciones@bancolombia.com")

    find("[data-bank-wizard-go='#{@first_key}']").click
    within_bank(@first_key) do
      find(".recognition-chip", text: /notificaciones@bancolombia.com/).find("[data-recognition-remove]").click
      assert_no_selector "input[name='senders[]'][value='notificaciones@bancolombia.com']", visible: :all
    end

    click_button I18n.t("money_sources.recognition.wizard.save_continue")
    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
    refute @bancolombia.reload.recognition_identifiers.confirmed
                       .exists?(kind: "sender", value: "notificaciones@bancolombia.com")
  end

  test "keeps the entered values and offers a retry when saving fails" do
    sign_in @user
    open_wizard

    within_bank(@first_key) do
      add_chip("senders", "notificaciones@bancolombia.com")
    end

    page.execute_script(<<~JS)
      window.__bankWizardRealFetch = window.fetch;
      window.fetch = function () { return Promise.reject(new Error("network down")); };
    JS

    click_button I18n.t("money_sources.recognition.wizard.save_continue")

    assert_selector "[data-bank-wizard-panel='#{@first_key}'] [data-bank-wizard-error]", visible: true, wait: 5
    assert_text I18n.t("money_sources.recognition.wizard.save_error")
    within_bank(@first_key) do
      assert_selector "input[name='senders[]'][value='notificaciones@bancolombia.com']", visible: :all
    end

    page.execute_script("window.fetch = window.__bankWizardRealFetch;")
    click_button I18n.t("money_sources.recognition.wizard.save_continue")

    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active", wait: 5
    assert_equal "Configurado", nav_state(@first_key)
  end

  test "shows the separate mail filter step without marking it as configured" do
    sign_in @user
    open_wizard

    within_bank(@first_key) do
      add_chip("senders", "notificaciones@bancolombia.com")
    end

    find("[data-testid='bank-wizard-filter-nav']").click

    assert_selector "[data-testid='bank-wizard-filter-step'].is-active"
    assert_selector "[data-testid='bank-wizard-filter-nav'].is-active"
    assert_text I18n.t("money_sources.recognition.wizard.filters_heading")
    assert_text I18n.t("money_sources.recognition.wizard.filters_body")
    assert_selector "a[href='https://support.google.com/mail/answer/6579?hl=es']"
    assert_no_text "Filtros configurados"

    click_button I18n.t("money_sources.recognition.wizard.filters_back_to_banks")
    assert_selector "[data-bank-wizard-panel='#{@first_key}'].is-active"
    within_bank(@first_key) do
      assert_selector "input[name='senders[]'][value='notificaciones@bancolombia.com']", visible: :all
    end

    click_button I18n.t("money_sources.recognition.wizard.save_continue")
    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
  end

  test "remains usable on a mobile viewport" do
    sign_in @user
    page.current_window.resize_to(390, 844)
    visit money_sources_recognition_path

    click_link I18n.t("money_sources.recognition.wizard.open")

    assert_modal_open
    assert_selector "[data-testid='bank-wizard-nav-item']", visible: :visible, count: 2
    assert_selector "[data-bank-wizard-next]", visible: :visible
    find("[data-bank-wizard-go='#{@second_key}']").click
    assert_selector "[data-bank-wizard-panel='#{@second_key}'].is-active"
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  teardown do
    page.current_window.resize_to(1400, 1000)
    sleep 0.2
  rescue StandardError
    # The driver may already be reset after a hard failure.
  end

  private

  def create_source(name:, bank:)
    @user.money_sources.create!(name: name, kind: "account", bank: bank, starting_balance: 0)
  end
  def bank_key(source)
    "legacy:#{source.bank.downcase}"
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "Correo electrónico", with: user.email, match: :first
    fill_in "Contraseña", with: "password123", match: :first
    click_button "Iniciar sesión"
    # The Devise redirect and the following visit must not race each other.
    assert_no_selector "input[name='user[email]']", wait: 10
  end

  def open_wizard
    visit money_sources_recognition_path
    click_link I18n.t("money_sources.recognition.wizard.open")
    assert_modal_open
  end

  def assert_modal_open
    assert_selector "#bank-setup-wizard", visible: :visible, wait: 10
    # Bootstrap ignores hide() while the opening transition is still running.
    sleep 0.4
  end

  def assert_modal_closed
    assert_no_selector "#bank-setup-wizard", visible: :visible, wait: 5
  end

  def within_bank(key, &block)
    within("[data-bank-wizard-panel='#{key}']", &block)
  end

  def add_chip(section, value)
    input = find("[data-bank-wizard-new-value='#{section}']")
    input.fill_in with: value
    find("[data-bank-wizard-add='#{section}']").click
    assert_selector ".recognition-chip", text: /#{Regexp.escape(value)}/
  end

  def nav_state(key)
    page.evaluate_script(
      "document.querySelector(\"[data-bank-wizard-go='#{key}'] [data-bank-wizard-nav-state]\").textContent"
    ).strip
  end
end
