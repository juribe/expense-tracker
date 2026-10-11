# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

module SourceRecognition
  # Sharing model after the bank-group redesign: ONE source of each bank
  # (the SEED) carries the confirmed sender/domain/subject/header values and
  # the matcher reuses them for every member of the group — without physical
  # copies. Product evidence (keywords, anchored last-four) always lives on
  # the individual source, and recognition settings never cross users.
  class MatcherBankGroupTest < ActiveSupport::TestCase
    setup do
      FinancialCatalogSeeder.run unless FinancialInstitution.exists?(slug: "davibank")
      @user = User.create!(name: "BG User", email: "bg@example.com", password: "password123")
      @other = User.create!(name: "BG Other", email: "bg_other@example.com", password: "password123")
      @davibank = FinancialInstitution.find_by!(slug: "davibank")
      @message = email_message
    end

    def email_message(from: "Davibank <avisos@davibank.com.co>",
                      subject: "Tu compra fue aprobada",
                      body: "DAVIbank te notifica una compra aprobada de 20,300.")
      { id: "msg-1", from: from, subject: subject, body_text: body, headers: [] }
    end

    def attach_source(user, name, last_four: nil, institution: @davibank, kind: "account")
      source = user.money_sources.create!(name: name, kind: kind, starting_balance: 0, bank: "Davibank",
                                          identifier: last_four)
      source.assign_institution_ref("FinancialInstitution:#{institution.id}") unless institution.nil?
      source.save!
      source
    end

    def configure_bank_sender(source)
      source.ensure_recognition.replace_identifiers(sender: [ "avisos@davibank.com.co" ])
      source
    end

    test "a member of the seed's group matches through the SHARED bank config" do
      seed = configure_bank_sender(attach_source(@user, "Davibank Semilla"))
      member = attach_source(@user, "Davibank Ahorros")

      matcher = Matcher.new(user: @user, message: @message)

      # The member belongs to the seed's group and matches ONLY through the
      # seed's confirmed sender (no per-member copies exist). Shared bank
      # evidence weighs LESS than the seed's own confirmations, so the seed
      # is the single winner when no product evidence breaks the tie.
      assert_equal seed.id, matcher.send(:bank_group_for, member)[:seed].id
      assert_empty member.recognition_identifiers
      assert_equal seed.id, Matcher.call(user: @user, message: @message).id
    end

    test "product evidence (anchored last-four) picks the member inside one group" do
      fifth = configure_bank_sender(attach_source(@user, "Davibank Semilla"))
      first = attach_source(@user, "Davibank Ahorros", last_four: "1111")
      second = attach_source(@user, "Davibank Nómina", last_four: "2222")

      first.ensure_recognition.replace_identifiers(keyword: [ "1111" ])
      message = email_message(body: "DAVIbank te notifica una compra con la tarjeta terminada en 1111.")

      assert_equal first, Matcher.call(user: @user, message: message)
    end

    test "another user's bank config never applies (privacy)" do
      configure_bank_sender(attach_source(@other, "Davibank Semilla Ajena"))
      attach_source(@user, "Davibank Ahorros")

      assert_nil Matcher.call(user: @user, message: @message)
    end

    test "two DIFFERENT banks matched at bank level stay ambiguous (bank evidence zeroed)" do
      nequi = FinancialInstitution.find_by!(slug: "nequi")
      davi_seed = configure_bank_sender(attach_source(@user, "Davibank Semilla"))
      davi_seed.recognition.replace_identifiers(sender: [ "davibank" ], domain: [ "davibank.com.co" ])
      nequi_seed = attach_source(@user, "Nequi Semilla", institution: nequi, kind: "wallet")
      nequi_seed.ensure_recognition.replace_identifiers(sender: [ "nequi" ])

      # One relay email naming both banks in the From display name: both
      # groups match at bank level → evidence zeroed, no winner.
      matcher = Matcher.new(user: @user, message: email_message(from: "Davibank Nequi <bounce@relay.co>"))

      assert matcher.send(:institution_ambiguous?)
      assert_nil matcher.call
    end

    test "a group without any configured member stays out of the matcher" do
      attach_source(@user, "Davibank Silenciosa")

      assert_nil Matcher.call(user: @user, message: @message)
    end
  end
end
