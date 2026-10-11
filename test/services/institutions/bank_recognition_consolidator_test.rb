# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

class InstitutionsBankRecognitionConsolidatorTest < ActiveSupport::TestCase
  setup do
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(slug: "davibank")
    @user = User.create!(name: "Consol User", email: "consol@example.com", password: "password123")
    @other = User.create!(name: "Consol Other", email: "consol_other@example.com", password: "password123")
  end

  def source!(user, name, institution: nil, bank: "Davibank")
    created = user.money_sources.create!(name: name, kind: "account", starting_balance: 0, bank: bank)
    unless institution.nil?
      created.assign_institution_ref("FinancialInstitution:#{institution.id}")
      created.save!
    end
    created
  end

  def bank_identifiers(source)
    return [] unless source.recognition

    source.recognition.recognition_identifiers
          .where(kind: %w[sender domain subject header], status: "confirmed")
  end

  test "moves bank-level values from members to the seed and keeps keywords in place" do
    @davibank = FinancialInstitution.find_by!(slug: "davibank")
    seed = source!(@user, "Davibank Semilla", institution: @davibank)
    member = source!(@user, "Davibank Ahorros", institution: @davibank)
    member.ensure_recognition.replace_identifiers(keyword: [ "ahorros" ])
    member.ensure_recognition.save!
    member.ensure_recognition.replace_identifiers(sender: [ "avisos@davibank.com.co" ])

    Institutions::BankRecognitionConsolidator.run

    # Seed owns the bank-level value now.
    assert_includes bank_identifiers(seed.reload).pluck(:value), "avisos@davibank.com.co"
    # The member keeps its PRODUCT keyword...
    assert_includes member.reload.recognition_identifiers.where(kind: "keyword").pluck(:value), "ahorros"
    # ...and loses the moved bank-level value (no duplicates at the group).
    assert_empty bank_identifiers(member.reload).pluck(:value)
  end

  test "exact values are not duplicated when the seed already holds them" do
    @davibank = FinancialInstitution.find_by!(slug: "davibank")
    seed = source!(@user, "Davibank Semilla", institution: @davibank)
    seed.ensure_recognition.replace_identifiers(sender: [ "avisos@davibank.com.co" ])
    seed.ensure_recognition.save!
    member = source!(@user, "Davibank Nómina", institution: @davibank)
    member.ensure_recognition.replace_identifiers(sender: [ "avisos@davibank.com.co" ])
    member.ensure_recognition.save!

    assert_difference "MoneySourceRecognitionIdentifier.count", -1 do
      Institutions::BankRecognitionConsolidator.run
    end

    seed.reload
    assert_equal 1, bank_identifiers(seed).where(value: "avisos@davibank.com.co").count
    assert_empty bank_identifiers(member.reload)
  end

  test "empty member recognition records are dropped after the move" do
    @davibank = FinancialInstitution.find_by!(slug: "davibank")
    seed = source!(@user, "Davibank Semilla", institution: @davibank)
    member = source!(@user, "Davibank Solo Banco", institution: @davibank)
    member.ensure_recognition.replace_identifiers(domain: [ "davibank.com.co" ])
    member.ensure_recognition.save!

    Institutions::BankRecognitionConsolidator.run

    seed.reload
    assert_includes bank_identifiers(seed).pluck(:value), "davibank.com.co"
    assert_nil member.reload.recognition
  end

  test "suggested (unreviewed) rows are left untouched" do
    @davibank = FinancialInstitution.find_by!(slug: "davibank")
    seed = source!(@user, "Davibank Semilla", institution: @davibank)
    member = source!(@user, "Davibank Pendientes", institution: @davibank)
    member.ensure_recognition.save!
    member.recognition.recognition_identifiers.create!(
      kind: "sender", value: "nuevo@davibank.biz", status: "suggested", origin: "gmail"
    )

    Institutions::BankRecognitionConsolidator.run

    member.reload
    assert member.recognition&.recognition_identifiers&.exists?(kind: "sender", status: "suggested")
    assert_empty bank_identifiers(seed.reload).select { |identifier| identifier.value == "nuevo@davibank.biz" }
  end

  test "LEGACY groups (folded bank token) consolidate without an attached entity" do
    seed = source!(@user, "Legacy Semilla")
    member = source!(@user, "Legacy Ahorros")
    member.ensure_recognition.replace_identifiers(sender: [ "avisos@legacy.co" ])
    member.ensure_recognition.save!

    Institutions::BankRecognitionConsolidator.run

    assert_includes bank_identifiers(seed.reload).pluck(:value), "avisos@legacy.co"
    assert_empty bank_identifiers(member.reload)
  end

  test "privacy: nothing crosses users" do
    mine = source!(@user, "Davibank Mia")
    mine.ensure_recognition.replace_identifiers(sender: [ "mios@davibank.co" ])
    mine.ensure_recognition.save!
    foreign = source!(@other, "Davibank Ajena")

    Institutions::BankRecognitionConsolidator.run

    assert_includes bank_identifiers(mine.reload).pluck(:value), "mios@davibank.co"
    assert_nil foreign.reload.recognition
  end

  test "dry run changes nothing (idempotent then commits on the real run)" do
    @davibank = FinancialInstitution.find_by!(slug: "davibank")
    seed = source!(@user, "Davibank Semilla", institution: @davibank)
    member = source!(@user, "Davibank Ahorros", institution: @davibank)
    member.ensure_recognition.replace_identifiers(sender: [ "avisos@davibank.com.co" ])
    member.ensure_recognition.save!

    Institutions::BankRecognitionConsolidator.run(dry_run: true)

    assert_empty bank_identifiers(seed.reload)
    assert_includes bank_identifiers(member.reload).pluck(:value), "avisos@davibank.com.co"

    Institutions::BankRecognitionConsolidator.run
    assert_includes bank_identifiers(seed.reload).pluck(:value), "avisos@davibank.com.co"

    # Re-run: idempotent, no second copies.
    assert_no_difference "MoneySourceRecognitionIdentifier.count" do
      Institutions::BankRecognitionConsolidator.run
    end
  end
end
