# frozen_string_literal: true

module FinancialSetups
  # Completer
  # Creates financial records from the completed wizard's persisted per-step
  # draft data. Runs the entire write inside a single database transaction.
  #
  # Supports both manually-entered sources and confirmed import sources
  # (with update-existing / create-new / ignore duplicate handling).
  #
  # Example: FinancialSetups::Completer.new(setup: setup).call
  class Completer
    Result = Struct.new(:ok?, :errors, :created_count, keyword_init: true)

    def initialize(setup:)
      @setup = setup
      @user = setup.user
    end

    def call
      ActiveRecord::Base.transaction do
        sources = []
        FinancialSetupWizard.source_step_keys.each do |step_key|
          sources.concat(create_for_step(step_key))
        end
        Result.new(ok?: true, errors: [], created_count: sources.length)
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(ok?: false, errors: [ e.message ], created_count: 0)
    end

    private

    def create_for_step(step_key)
      choice = @setup.choice_for(step_key)
      return [] if choice.blank? || choice == "skip"

      choice == "import" ? create_imports(step_key) : create_manuals(step_key)
    end

    def create_manuals(step_key)
      kind = FinancialSetupWizard.step(step_key).kind
      rows = @setup.draft_sources(step_key).reject { |row| blank_manual_row?(row) }
      rows.map { |row| create_manual_source(row, kind) }
    end

    def blank_manual_row?(row)
      %w[name bank balance starting_balance outstanding_balance].all? do |field|
        row[field].to_s.strip.blank?
      end
    end

    def create_manual_source(row, kind)
      source = @user.money_sources.build(
        name: row["name"],
        kind: kind,
        bank: row["bank"],
        starting_balance: row["starting_balance"] || row["balance"] || 0
      )

      if %w[credit_card loan].include?(kind)
        build_credit_account(source, row)
      end

      source.save!
      source
    end

    def build_credit_account(source, row)
      ca = source.build_credit_account(
        credit_limit: row["credit_limit"],
        interest_rate: row["interest_rate"],
        interest_rate_type: row["interest_rate_type"],
        card_brand: row["card_brand"],
        card_last_four: row["card_last_four"],
        principal_amount: row["principal_amount"],
        outstanding_balance: row["outstanding_balance"],
        installment_amount: row["monthly_payment"],
        payment_frequency: row["payment_frequency"],
        statement_day: row["statement_day"]
      )
      ca
    end

    def create_imports(step_key)
      kind = FinancialSetupWizard.step(step_key).kind
      import = @setup.import_state(step_key)
      sources = import["sources"] || []
      duplicates = import["duplicates"] || {}

      sources.flat_map do |entry|
        choice = duplicate_choice(duplicates, entry)
        case choice
        when "ignore"
          []
        when "update"
          update_existing(entry, kind)
        else
          create_from_statement(entry, kind)
        end
      end
    end

    # The review screen stores duplicate choices as plain strings
    # ("update"/"create"/"ignore"); the pipeline stores the hash form. Both can
    # appear depending on how far the user progressed, so accept either.
    def duplicate_choice(duplicates, entry)
      raw = duplicates[duplicate_key(entry)]
      raw.is_a?(Hash) ? raw["choice"] : raw
    end

    def duplicate_key(entry)
      FinancialSetupWizard.duplicate_key(entry)
    end

    def find_existing(entry)
      parser = ParsedStatement.new(entry)
      StatementDuplicateDetector.new(user: @user).duplicate_of?(parser)
    end

    def update_existing(entry, kind)
      source = find_existing(entry)
      return [] if source.nil?

      source.update!(name: entry["name"], bank: entry["bank"]) if entry["name"].present?
      source
    end

    def create_from_statement(entry, kind)
      source = @user.money_sources.build(
        name: entry["name"] || entry["bank"],
        kind: kind,
        bank: entry["bank"],
        starting_balance: entry["balance"] || 0,
        identifier: entry["identifier"].presence
      )

      if %w[credit_card loan].include?(kind)
        build_credit_account(source, entry)
      end
      source.save!
      source
    end
  end
end
