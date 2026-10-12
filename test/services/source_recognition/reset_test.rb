# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/seed_data/financial_catalog_seeder")

module SourceRecognition
  class ResetTest < ActiveSupport::TestCase
  setup do
    FinancialCatalogSeeder.run unless FinancialInstitution.exists?(canonical_name: "Bancolombia")
    @user = User.create!(name: "Reset User", email: "reset_user@example.com", password: "password123")
      @source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 0, bank: "Davibank")
      recognition = @source.ensure_recognition
      recognition.replace_identifiers(keyword: [ "davibank" ], sender: [ "avisos@davibank.co" ])
      @connection = GmailConnection.create!(user: @user, email: "reset_user@gmail.com", active: true,
                                            access_token: "AT",
                                            search_config: { senders: [ "x@bank.co" ] },
                                            setup_suggestions: { "scanned" => 3 })
      ProcessedEmail.create!(provider: "gmail", message_id: "reset-msg-1", user: @user, status: "processed")
    end

    test "dry run reports without deleting anything" do
      counts = Reset.run(dry_run: true)

      assert counts[:recognitions].positive?
      assert_equal 1, MoneySourceRecognition.count
      assert_equal({ "senders" => [ "x@bank.co" ] }, @connection.reload.search_config)
    end

    test "real run wipes recognition and gmail email config, keeps OAuth + processed emails" do
      counts = Reset.run

      assert_equal 2, counts[:identifiers]
      assert_equal 0, MoneySourceRecognition.count
      assert_equal 0, MoneySourceRecognitionIdentifier.count
      assert_equal({}, @connection.reload.search_config)
      assert_equal({}, @connection.reload.setup_suggestions)

      # OAuth untouched
      assert @connection.reload.active?
      assert_equal "reset_user@gmail.com", @connection.email
      assert_equal "AT", @connection.access_token

      # Financial data untouched
      assert MoneySource.exists?(@source.id)
      assert ProcessedEmail.exists?(message_id: "reset-msg-1")
      assert FinancialInstitution.count.positive? # shared catalog stays
    end

    test "re-running is a no-op" do
      Reset.run

      assert_nothing_raised do
        assert_equal 0, Reset.run[:recognitions]
      end
    end
  end
end
