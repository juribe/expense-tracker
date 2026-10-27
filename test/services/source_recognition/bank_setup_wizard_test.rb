# frozen_string_literal: true

require "test_helper"

class SourceRecognition::BankSetupWizardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Wizard User",
      email: "bank_wizard_service_#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  test "builds one step per non-cash bank with its confirmed bank-level values" do
    davibank = create_source(name: "Cuenta Davibank", bank: "Davibank")
    davibank.ensure_recognition.replace_identifiers(
      keyword: [ "cuenta" ],
      sender: [ "notificaciones@davibank.com" ],
      domain: [ "davibank.com" ],
      subject: [ "Compra aprobada" ]
    )
    create_source(name: "Efectivo", kind: "cash", bank: "")

    steps = SourceRecognition::BankSetupWizard.new(bank_groups).steps

    assert_equal [ "Davibank" ], steps.map(&:label)
    step = steps.first
    assert step.configured
    assert_equal [ "notificaciones@davibank.com", "davibank.com" ], step.senders
    assert_equal [ "Compra aprobada" ], step.subjects
    assert_equal davibank.id, step.source_id
    refute_includes step.senders, "cuenta"
  end

  test "a keyword-only configuration is not a configured bank" do
    source = create_source(name: "Cuenta Davibank", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: [ "cuenta" ])

    step = SourceRecognition::BankSetupWizard.new(bank_groups).steps.first

    refute step.configured
    assert_empty step.senders
    assert_empty step.subjects
  end

  test "reuses the existing sibling suggestions for the bank step" do
    seed = create_source(name: "Cuenta Davibank", bank: "Davibank")
    sibling = create_source(name: "Tarjeta Davibank", kind: "credit_card", bank: "Davibank")
    sibling.ensure_recognition.replace_identifiers(
      sender: [ "notificaciones@davibank.com" ],
      subject: [ "Transferencia realizada" ]
    )

    step = SourceRecognition::BankSetupWizard.new(bank_groups).steps.find { |s| s.source_id == seed.id }

    assert_includes step.suggestions[:senders].map { |suggestion| suggestion[:value] },
                    "notificaciones@davibank.com"
    assert_includes step.suggestions[:subjects].map { |suggestion| suggestion[:value] },
                    "Transferencia realizada"
  end

  private

  def create_source(name:, kind: "account", bank: "Davibank")
    @user.money_sources.create!(name: name, kind: kind, bank: bank, starting_balance: 0)
  end

  # Mirrors the controller's grouping output, the input this service consumes.
  def bank_groups
    groups = SourceRecognition::BankGrouping.groups_for(@user.money_sources.payment_sources.includes(:recognition_identifiers))
    groups.values.map do |members|
      seed = members.min_by { |member| [ member.created_at, member.id ] }
      {
        key: SourceRecognition::BankGrouping.key(members.first),
        label: members.first.institution_name.presence || members.first.bank,
        cash_only: members.all? { |member| member.kind == "cash" },
        seed: seed,
        members: members,
        pending: 0
      }
    end
  end
end
