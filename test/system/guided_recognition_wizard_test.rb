# frozen_string_literal: true

require "application_system_test_case"

class GuidedRecognitionWizardSystemTest < ApplicationSystemTestCase
  driven_by :selenium_chrome_headless

  setup do
    @user = User.create!(
      name: "Guided System User",
      email: "guided_system_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    @user.confirm
    @account = create_source(name: "Ahorros Davibank", kind: "account", bank: "Davibank")
    @card = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda", identifier: "7273")
    @cash = create_source(name: "Efectivo", kind: "cash")
    page.driver.browser.manage.window.resize_to(1440, 1000)
  end

  test "opens as a modal and keeps aliases mirrored while navigating and saving" do
    sign_in @user
    visit money_sources_recognition_path

    click_link I18n.t("money_sources.recognition.guided.open")

    assert_modal_open
    assert_text I18n.t("money_sources.recognition.guided.intro_page_title")
    assert_selector "[data-guided-intro]"
    assert_selector "[data-testid='guided-source-item']", count: 3
    assert_selector "form[data-guided-step-form]:not(.d-none)", count: 0
    assert_selector "[data-testid='guided-save']", text: I18n.t("money_sources.recognition.guided.start")

    page.save_screenshot(Rails.root.join(".tmp/guided-wizard-intro.png").to_s)

    scroll_and_click(find("[data-testid='guided-save']"))
    assert_selector "form[data-guided-step-index='0']:not(.d-none)", wait: 10
    # The sample always underlines a reference, even before any keyword exists.
    assert_selector "form[data-guided-step-index='0'] [data-testid='guided-email-body'] mark.guided-highlight"
    assert_no_text "Criterios del banco"

    page.save_screenshot(Rails.root.join(".tmp/guided-wizard-initial.png").to_s)

    within "form[data-guided-step-index='0']" do
      find("[data-guided-keyword-input]").fill_in with: "gold"
      scroll_and_click(find("[data-guided-keyword-add]"))
      assert_selector "[data-testid='guided-alias-chip']", text: /\Agold\z/, wait: 5

      # Deleting from the alias side also removes the shared criterion.
      alias_chip = find("[data-testid='guided-alias-chip']", text: /\Agold\z/)
      scroll_and_click(alias_chip.find("[data-guided-alias-remove]"))
      assert_selector "input[name='keywords[]'][value='gold']", count: 0, visible: :all, wait: 5
      assert_selector "[data-testid='guided-alias-chip']", text: /\Agold\z/, count: 0

      find("[data-guided-keyword-input]").fill_in with: "gold"
      scroll_and_click(find("[data-guided-keyword-add]"))

      find("[data-guided-alias-input]").fill_in with: "mi gold"
      scroll_and_click(find("[data-guided-alias-add]"))
      assert_selector "input[name='keywords[]'][value='mi gold']", visible: :all, wait: 5
      assert_text "Ayer pagué $120.000 con mi gold."

      # Deleting from the email side also removes the alias chip.
      scroll_and_click(find("[data-chip-value='mi gold'] [data-recognition-remove]"))
      assert_selector "[data-testid='guided-alias-chip']", text: /mi gold/, count: 0, wait: 5

      find("[data-guided-alias-input]").fill_in with: "mi gold"
      scroll_and_click(find("[data-guided-alias-add]"))
      assert_selector "[data-testid='guided-alias-chip']", count: 2
      assert_selector "input[name='keywords[]'][value='gold']", visible: :all
      assert_selector "input[name='keywords[]'][value='mi gold']", visible: :all

      # A value accepted from the email suggestion block must also be
      # removable from the alias side (it has no data-chip-value attribute).
      suggestion = find(".recognition-chip-suggested[data-suggested-for='keywords'][data-suggested-value='ahorros']")
      scroll_and_click(suggestion.find("[data-recognition-accept-suggestion]"))
      assert_selector "[data-testid='guided-alias-chip']", text: /\Aahorros\z/, wait: 5

      accepted_alias = find("[data-testid='guided-alias-chip']", text: /\Aahorros\z/)
      scroll_and_click(accepted_alias.find("[data-guided-alias-remove]"))
      assert_selector "input[name='keywords[]'][value='ahorros']", count: 0, visible: :all, wait: 5
      assert_selector "[data-testid='guided-alias-chip']", text: /\Aahorros\z/, count: 0

      # Comma-separated input becomes one tag per value.
      find("[data-guided-keyword-input]").fill_in with: "tc credito, tc caja social"
      scroll_and_click(find("[data-guided-keyword-add]"))
      assert_selector "[data-testid='guided-alias-chip']", text: /\Atc credito\z/, wait: 5
      assert_selector "[data-testid='guided-alias-chip']", text: /\Atc caja social\z/
      assert_selector "[data-testid='guided-alias-chip']", text: /tc credito, tc caja social/, count: 0
      assert_selector "input[name='keywords[]'][value='tc credito']", visible: :all
      assert_selector "input[name='keywords[]'][value='tc caja social']", visible: :all

      [ "tc credito", "tc caja social" ].each do |value|
        chip = find("[data-testid='guided-alias-chip']", text: /\A#{Regexp.escape(value)}\z/)
        scroll_and_click(chip.find("[data-guided-alias-remove]"))
      end
      assert_selector "input[name='keywords[]'][value='tc credito']", count: 0, visible: :all, wait: 5
      assert_selector "input[name='keywords[]'][value='tc caja social']", count: 0, visible: :all
    end

    page.save_screenshot(Rails.root.join(".tmp/guided-wizard-desktop.png").to_s)

    scroll_and_click(find("[data-testid='guided-save']"))
    assert_selector "form[data-guided-step-index='1']:not(.d-none)", wait: 10

    # Switching back keeps the unsaved/saved state and the same modal.
    find("[data-guided-go='0']").click
    assert_selector "form[data-guided-step-index='0']:not(.d-none)", wait: 5
    within "form[data-guided-step-index='0']" do
      assert_selector "[data-testid='guided-alias-chip']", text: /gold/
      assert_selector "[data-testid='guided-alias-chip']", text: /mi gold/
    end

    identifiers = @account.reload.recognition_identifiers.confirmed.where(kind: "keyword").pluck(:value)
    assert_equal [ "gold", "mi gold" ], identifiers

    # Save the remaining steps and finish from the last one.
    scroll_and_click(find("[data-testid='guided-save']"))
    assert_selector "form[data-guided-step-index='1']:not(.d-none)", wait: 10
    scroll_and_click(find("[data-testid='guided-save']"))
    assert_selector "form[data-guided-step-index='2']:not(.d-none)", wait: 10
    within "[data-testid='guided-save']" do
      assert_text I18n.t("money_sources.recognition.guided.finish")
    end
    scroll_and_click(find("[data-testid='guided-save']"))

    assert_current_path money_sources_recognition_path, wait: 10
    assert_no_selector "#guided-wizard-modal.show"
  end

  test "cash hides email criteria, closes and reopens, and saves aliases on exit" do
    @account.destroy!
    @card.destroy!

    sign_in @user
    visit money_sources_recognition_path
    click_link I18n.t("money_sources.recognition.guided.open")
    assert_modal_open

    assert_no_selector "[data-guided-step-form] [data-testid='guided-email-section']"

    find("[data-testid='guided-close']").click
    assert_no_selector "#guided-wizard-modal.show", wait: 10

    # Reopening from the same page reuses the rendered modal without a reload.
    click_link I18n.t("money_sources.recognition.guided.open")
    assert_modal_open

    scroll_and_click(find("[data-testid='guided-save']"))
    assert_selector "form[data-guided-step-index='0']:not(.d-none)", wait: 10
    assert_selector "form[data-guided-step-index='0'] [data-testid='recognition-suggested-block']", count: 1

    within "form[data-guided-step-index='0']" do
      find("[data-guided-alias-input]").fill_in with: "efectivo"
      scroll_and_click(find("[data-guided-alias-add]"))
    end

    page.driver.browser.manage.window.resize_to(390, 844)
    sleep 0.3
    page.save_screenshot(Rails.root.join(".tmp/guided-wizard-mobile.png").to_s)
    page.driver.browser.manage.window.resize_to(1440, 1000)
    sleep 0.3

    scroll_and_click(find("[data-testid='guided-exit-save']"))

    assert_current_path money_sources_recognition_path, wait: 10
    assert_no_selector "#guided-wizard-modal.show"
    assert_equal [ "efectivo" ], @cash.reload.recognition_identifiers.confirmed.pluck(:value)
  end

  private

  def create_source(name:, kind:, **opts)
    @user.money_sources.create!({ name: name, kind: kind, starting_balance: 0 }.merge(opts))
  end

  def assert_modal_open
    assert_selector "#guided-wizard-modal.show", visible: :visible, wait: 10
    sleep 0.3
  end

  def sign_in(user)
    visit new_user_session_path
    fill_in "user_email", with: user.email
    fill_in "user_password", with: "password123"
    click_button "Iniciar sesión"
    assert_selector "aside.left-sidebar", wait: 10
  end
end
