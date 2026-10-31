# frozen_string_literal: true

require "test_helper"

class SourceRecognition::GuidedWizardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Guided Wizard Presenter",
      email: "guided_wizard_presenter_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_source(name:, kind:, **opts)
    @user.money_sources.create!({ name: name, kind: kind, starting_balance: 0 }.merge(opts))
  end

  test "builds one ordered step per payment source" do
    create_source(name: "Gold", kind: "credit_card")
    create_source(name: "Ahorros", kind: "account")
    create_source(name: "Crédito carro", kind: "loan")
    create_source(name: "Bolsillo", kind: "pocket")

    steps = SourceRecognition::GuidedWizard.for_user(@user)

    assert_equal [ "Ahorros", "Gold" ], steps.map { |step| step.current.name }
    assert_equal [ 0, 1 ], steps.map(&:index)
    assert_equal [ 2, 2 ], steps.map(&:total)
    assert_equal "Ahorros", steps.first.current.name
  end

  test "resolves only the user's own sources" do
    mine = create_source(name: "Mi cuenta", kind: "account")
    other_user = User.create!(name: "Other", email: "guided_presenter_other_#{SecureRandom.hex(4)}@example.com",
                              password: "password123")
    foreign = other_user.money_sources.create!(name: "Cuenta ajena", kind: "account", starting_balance: 0)

    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: foreign.id)

    assert_equal [ mine ], wizard.sources
    assert_equal mine, wizard.current
  end

  test "counts only sources with confirmed recognition as configured" do
    configured = create_source(name: "Ahorros", kind: "account")
    configured.ensure_recognition.replace_identifiers(keyword: [ "ahorros" ])
    pending = create_source(name: "Gold", kind: "credit_card")
    pending.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "keyword", value: "gold", status: "suggested", origin: "gmail"
    )

    steps = SourceRecognition::GuidedWizard.for_user(@user)

    assert steps.find { |step| step.current == configured }.configured?
    assert_not steps.find { |step| step.current == pending }.configured?
  end

  test "cash sources have no email preview and keep natural-language aliases" do
    cash = create_source(name: "Efectivo", kind: "cash")
    cash.ensure_recognition.replace_identifiers(keyword: [ "efectivo" ])

    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: cash.id)

    assert_not wizard.email_applicable?
    assert_nil wizard.email_preview
    assert_equal [ "efectivo" ], wizard.alias_values
    assert_equal cash, wizard.current
  end

  test "builds the email preview from the existing bank-level configuration" do
    sibling = create_source(name: "Davivienda Clásica", kind: "credit_card", bank: "Davivienda")
    sibling.ensure_recognition.replace_identifiers(
      sender: [ "notificaciones@davivienda.com" ], subject: [ "Compra aprobada" ]
    )
    card = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda", identifier: "7273")
    card.ensure_recognition.replace_identifiers(keyword: %w[gold 7273])

    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: card.id)

    assert wizard.email_applicable?
    assert_equal "notificaciones@davivienda.com", wizard.email_preview[:sender_address]
    assert_equal "Compra aprobada", wizard.email_preview[:subject]
    assert_match(/Davivienda Gold/, wizard.email_preview[:body])
    assert_match(/7273/, wizard.email_preview[:body])
    assert_equal %w[gold 7273], wizard.email_preview[:highlights]
    assert wizard.email_preview[:configured_match]
  end

  test "always highlights a reference when no criteria match" do
    account = create_source(name: "Cuenta Nu", kind: "account", bank: "Nu")
    account_wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: account.id)

    assert_equal [ "Cuenta Nu" ], account_wizard.email_preview[:highlights]
    assert_equal "Cuenta Nu", account_wizard.email_preview[:fallback_highlight]
    assert_not account_wizard.email_preview[:configured_match]

    card = create_source(name: "Nu Clásica", kind: "credit_card", bank: "Nu", identifier: "1842")
    card_wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: card.id)

    assert_equal [ "1842" ], card_wizard.email_preview[:highlights]
    assert_equal "1842", card_wizard.email_preview[:fallback_highlight]
    assert_not card_wizard.email_preview[:configured_match]
  end

  test "alias values include only confirmed keywords" do
    source = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda")
    source.ensure_recognition.replace_identifiers(keyword: [ "tarjeta gold" ])
    source.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "keyword", value: "mi gold", status: "suggested", origin: "gmail"
    )
    source.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "keyword", value: "tc gold", status: "dismissed", origin: "user"
    )

    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: source.id)

    assert_equal [ "tarjeta gold" ], wizard.alias_values
  end

  test "builds the WhatsApp example from the configured alias" do
    source = create_source(name: "Davivienda Gold", kind: "credit_card", bank: "Davivienda")
    source.ensure_recognition.replace_identifiers(keyword: [ "tarjeta gold", "mi gold" ])

    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: source.id)
    whatsapp = wizard.whatsapp_example

    assert_equal "tarjeta gold", whatsapp[:highlight]
    assert_match(/tarjeta gold/, whatsapp[:text])
    assert_equal "whatsapp", whatsapp[:channel]
  end

  test "falls back to the source name when no alias is configured" do
    source = create_source(name: "Nequi", kind: "wallet")
    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: source.id)

    whatsapp = wizard.whatsapp_example

    assert_equal "nequi", whatsapp[:highlight]
    assert_empty wizard.alias_values
  end

  test "exposes existing suggestions without persisting them" do
    source = create_source(name: "Ahorros Davibank", kind: "account", bank: "Davibank")
    wizard = SourceRecognition::GuidedWizard.new(user: @user, source_id: source.id)

    assert wizard.suggestions[:keywords].any?
    assert_nil source.reload.recognition
    assert_not source.recognition_configured?
  end
end
