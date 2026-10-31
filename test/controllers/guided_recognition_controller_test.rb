# frozen_string_literal: true

require "test_helper"

class GuidedRecognitionControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Guided Wizard User",
      email: "guided_wizard_ctrl_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
    sign_in @user
  end

  def create_source(name:, kind:, **opts)
    @user.money_sources.create!({ name: name, kind: kind, starting_balance: 0 }.merge(opts))
  end

  test "recognition page offers the guided modal without replacing the existing options" do
    create_source(name: "Ahorros", kind: "account")

    get money_sources_recognition_path

    assert_response :success
    assert_select "a[data-testid='guided-recognition-open'][href=?]",
                  money_sources_recognition_path(guided: 1)
    assert_select "a[data-testid='guided-recognition-open'][data-guided-wizard-open]"
    assert_select "[data-testid='guided-wizard-modal']", count: 0
    # The manual configuration and the bank wizard keep their existing entries.
    assert_select "[data-testid='bank-wizard-open']"
    assert_select "[data-testid='recognition-help-btn']"
  end

  test "guided modal renders every payment source as a step with compact progress" do
    create_source(name: "Ahorros", kind: "account")
    create_source(name: "Efectivo", kind: "cash")
    create_source(name: "Gold", kind: "credit_card")
    create_source(name: "Crédito carro", kind: "loan")
    create_source(name: "Bolsillo viaje", kind: "pocket")

    get money_sources_recognition_path(guided: 1)

    assert_response :success
    assert_select "[data-testid='guided-wizard-modal']"
    assert_select "[data-guided-intro]"
    assert_select "[data-guided-intro] h1", text: I18n.t("money_sources.recognition.guided.intro_page_title")
    assert_select "[data-guided-intro] .guided-mail mark.guided-highlight", text: /GOLD/
    assert_select "[data-guided-intro] .guided-chat.is-whatsapp"
    assert_select "[data-guided-intro] .guided-chat.is-ai"
    assert_select "form[data-guided-step-form]", count: 3
    assert_select "form[data-guided-step-form]:not(.d-none)", count: 0
    assert_select "[data-testid='guided-source-item']", count: 3
    assert_select "[data-testid='guided-source-item'].is-active", count: 0
    assert_select "[data-testid='guided-source-item'] [data-testid='guided-source-item-name']",
                  text: "Crédito carro", count: 0
    assert_select "[data-testid='guided-source-item'] [data-testid='guided-source-item-name']",
                  text: "Bolsillo viaje", count: 0
    assert_select "[data-testid='guided-progress-text']", text: "0 de 3"
    assert_select "[data-guided-progress-bar].et-w-0"
    assert_select "[data-testid='guided-save']", text: I18n.t("money_sources.recognition.guided.start")
    assert_select "[data-testid='guided-source-item'][data-guided-go]"
  end

  test "each source shows email and alias configuration side by side" do
    card = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda", identifier: "7273")

    get money_sources_recognition_path(guided: 1)

    step = "form[data-guided-source-id='#{card.id}']"
    assert_select "#{step} .guided-two-col:not(.is-single) > .guided-panel", count: 2
    assert_select "#{step} .guided-example", count: 2
    assert_select "#{step} .guided-add-values", count: 2
    assert_select "#{step} [data-testid='guided-email-section'] .guided-add-row input[data-guided-keyword-input]"
    assert_select "#{step} [data-testid='guided-email-section'] .guided-add-row button[data-guided-keyword-add]"
    assert_select "#{step} [data-testid='guided-alias-section'] .guided-add-row input[data-guided-alias-input]"
    assert_select "#{step} [data-testid='guided-alias-section'] .guided-add-row button[data-guided-alias-add]"
    assert_select "#{step} [data-recognition-add]", count: 0
    assert_select "#{step} .guided-name-chip", count: 0
    assert_select "#{step} [data-testid='guided-email-section'] .guided-add-values",
                  text: /#{I18n.t('money_sources.recognition.guided.criteria_to_add')}/
    assert_select "#{step} [data-testid='guided-alias-section'] .guided-add-values",
                  text: /#{I18n.t('money_sources.recognition.guided.alias_to_add')}/
    assert_select "#{step} [data-testid='guided-email-section']"
    assert_select "#{step} [data-testid='guided-alias-section']"
    assert_select "#{step} [data-testid='guided-email-body']"
    assert_select "#{step} [data-testid='guided-whatsapp-example']"
    assert_select "#{step} .guided-panel-head", text: /#{I18n.t('money_sources.recognition.guided.email_config_title')}/
    assert_select "#{step} .guided-panel-head", text: /#{I18n.t('money_sources.recognition.guided.alias_config_title')}/
  end

  test "never exposes another user's sources" do
    mine = create_source(name: "Mi cuenta", kind: "account")
    other_user = User.create!(name: "Other", email: "guided_foreign_#{SecureRandom.hex(4)}@example.com",
                              password: "password123")
    other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account", starting_balance: 0)

    get money_sources_recognition_path(guided: 1)

    assert_response :success
    assert_select "form[data-guided-step-form]", count: 1
    assert_select "[data-testid='guided-source-name']", text: mine.name
    assert_no_match(/Cuenta Ajena/, response.body)
  end

  test "reflects each source's configured state" do
    create_source(name: "Ahorros", kind: "account")
    card = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda")
    card.ensure_recognition.replace_identifiers(keyword: [ "gold" ])

    get money_sources_recognition_path(guided: 1)

    assert_response :success
    assert_select "form[data-guided-source-id='#{card.id}'][data-configured='true']"
    assert_select "[data-testid='guided-source-item'][data-configured='true'] [data-testid='guided-source-state']",
                  text: I18n.t("money_sources.recognition.guided.state_configured")
    assert_select "[data-testid='guided-progress-text']", text: "1 de 2"
    assert_select "[data-guided-progress-bar].et-w-50"
  end

  test "cash sources skip email criteria and keep the natural-language section" do
    create_source(name: "Ahorros", kind: "account")
    cash = create_source(name: "Efectivo", kind: "cash")

    get money_sources_recognition_path(guided: 1)

    assert_response :success
    assert_select "form[data-guided-source-id='#{cash.id}'] [data-testid='guided-email-section']", count: 0
    assert_select "form[data-guided-source-id='#{cash.id}'] [data-testid='guided-alias-section']", count: 1
    assert_select "form[data-guided-source-id='#{cash.id}'] [data-testid='guided-whatsapp-example']"
    assert_select "form[data-guided-source-id='#{cash.id}'] [data-testid='guided-ai-example']", count: 0
    assert_select "form[data-guided-source-id='#{cash.id}'] [data-testid='recognition-suggested-block']", count: 1
  end

  test "shows the email example with the confirmed criteria highlighted" do
    source = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda", identifier: "7273")
    source.ensure_recognition.replace_identifiers(keyword: %w[gold 7273])

    get money_sources_recognition_path(guided: 1)

    assert_response :success
    step = "form[data-guided-source-id='#{source.id}']"
    assert_select "#{step} [data-testid='guided-email-section']"
    assert_select "#{step} [data-testid='guided-email-body'] mark.guided-highlight", count: 2
    assert_select "#{step} [data-testid='guided-email-body'] mark.guided-highlight", text: /gold/i
    assert_select "#{step} [data-testid='guided-email-body'] mark.guided-highlight", text: "7273"
    assert_select "#{step} [data-recognition-chips='keywords'] input[name='keywords[]'][value='gold']", visible: :all
    assert_select "#{step} [data-recognition-chips='keywords'] input[name='keywords[]'][value='7273']", visible: :all
    assert_select "#{step} [data-testid='guided-alias-chip']", count: 2
  end

  test "renders the existing suggestions without confirming or persisting them" do
    source = create_source(name: "Ahorros Davibank", kind: "account", bank: "Davibank")

    get money_sources_recognition_path(guided: 1)

    assert_response :success
    assert_select "form[data-guided-source-id='#{source.id}'] .recognition-chip-suggested[data-suggested-for='keywords']"
    assert_not source.reload.recognition_configured?
    assert_nil source.reload.recognition
  end

  test "renders the WhatsApp example for the selected source" do
    source = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda")
    source.ensure_recognition.replace_identifiers(keyword: [ "tarjeta gold" ])

    get money_sources_recognition_path(guided: 1)

    step = "form[data-guided-source-id='#{source.id}']"
    assert_select "#{step} [data-testid='guided-whatsapp-example'] mark.guided-highlight", text: /tarjeta gold/i
    assert_select "#{step} [data-testid='guided-whatsapp-detected']", text: /Davivienda Gold/
    assert_select "#{step} [data-testid='guided-ai-example']", count: 0
  end

  test "the modal reuses the existing recognition endpoint and keeps the tip" do
    first = create_source(name: "Ahorros", kind: "account")
    create_source(name: "Gold", kind: "credit_card")

    get money_sources_recognition_path(guided: 1)

    assert_select "form[data-guided-source-id='#{first.id}'][action='#{money_source_recognition_path(first.id)}'][method='post']"
    assert_select "form[data-guided-source-id='#{first.id}'] input[name='guided'][value='1']", visible: :all
    assert_select "[data-testid='guided-wizard-modal'][data-finish-url='#{money_sources_recognition_path}']"
    assert_select "[data-testid='guided-wizard-modal'][data-label-finish='#{I18n.t('money_sources.recognition.guided.finish')}']"
    assert_select "[data-testid='guided-previous'].d-none"
    assert_select "[data-testid='guided-save']", text: I18n.t("money_sources.recognition.guided.start")
    assert_select ".guided-foot", text: /#{I18n.t('money_sources.recognition.guided.footer_tip')}/
    # Bank-level criteria live in their own bank modal, not in this wizard.
    assert_select ".guided-bank-criteria", count: 0
    assert_select "[data-testid='guided-bank-edit']", count: 0
    assert_no_match(/Criterios del banco/, response.body)
  end

  test "the email example always highlights a reference even without criteria" do
    account = create_source(name: "Cuenta Nu", kind: "account", bank: "Nu")
    card = create_source(name: "Nu Clásica", kind: "credit_card", bank: "Nu", identifier: "1842")

    get money_sources_recognition_path(guided: 1)

    account_step = "form[data-guided-source-id='#{account.id}']"
    assert_select "#{account_step} [data-testid='guided-email-body'] mark.guided-highlight",
                  text: /Cuenta Nu/
    assert_select "#{account_step} [data-guided-caption-example]:not(.d-none)"
    assert_select "#{account_step} [data-guided-caption-example]", text: /Ejemplo:/

    card_step = "form[data-guided-source-id='#{card.id}']"
    assert_select "#{card_step} [data-testid='guided-email-body'] mark.guided-highlight", text: "1842"
  end

  test "the last step's label is provided for the modal footer" do
    get money_sources_recognition_path(guided: 1)

    assert_select "[data-testid='guided-wizard-modal'][data-label-save='#{I18n.t('money_sources.recognition.guided.save_continue')}']"
    assert_select "[data-testid='guided-wizard-modal'][data-label-finish='#{I18n.t('money_sources.recognition.guided.finish')}']"
  end

  test "an empty list renders the modal empty state with a link to create a source" do
    get money_sources_recognition_path(guided: 1)

    assert_response :success
    assert_select "[data-testid='guided-wizard-modal']"
    assert_select "[data-testid='guided-empty']"
    assert_select "[data-testid='guided-empty'] a[href=?]", new_money_source_path
    assert_select "form[data-guided-step-form]", count: 0
    assert_select "[data-testid='guided-progress-text']", count: 0
  end

  test "guided JSON save persists the step and returns its new status" do
    source = create_source(name: "Ahorros", kind: "account")

    patch money_source_recognition_path(source.id), params: { keywords: [ "ahorros" ], guided: "1" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal true, body["configured"]
    assert_equal [ "ahorros" ], body["keywords"]
    assert source.reload.recognition_configured?
  end

  test "guided JSON save can clear the keywords and reports the source as pending" do
    source = create_source(name: "Ahorros", kind: "account")
    source.ensure_recognition.replace_identifiers(keyword: [ "ahorros" ])

    patch money_source_recognition_path(source.id), params: { keywords: [ "" ], guided: "1" }, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal false, body["configured"]
    assert_equal [], body["keywords"]
    assert_not source.reload.recognition_configured?
  end

  test "the existing manual save still returns to the recognition page" do
    source = create_source(name: "Ahorros", kind: "account")

    patch money_source_recognition_path(source.id), params: { keywords: [ "ahorros" ] }

    assert_redirected_to money_sources_recognition_path
    assert source.reload.recognition_configured?
  end
end
