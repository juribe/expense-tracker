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
      return [] if choice.blank?
      # "skip" only means skip when the step has nothing in it. Sources can be
      # present with a skip choice when the user continued with what they had
      # already added (the step screen's "Continuar" option), so create from
      # data presence, merging both stores.
      return [] if choice == "skip" && !step_has_sources?(step_key)

      create_manuals(step_key) + create_imports(step_key)
    end

    def step_has_sources?(step_key)
      @setup.draft_sources(step_key).any? { |row| !blank_manual_row?(row) } ||
        Array(@setup.import_state(step_key)["sources"]).any?
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
        starting_balance: starting_balance_for(kind, row),
        identifier: row["identifier"].presence
      )

      if %w[credit_card loan].include?(kind)
        build_credit_account(source, row)
      end

      source.save!
      create_payment_recurrence(source, row)
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
        installment_count: row["installment_count"],
        installments_paid: row["installments_paid"],
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
        starting_balance: starting_balance_for(kind, entry),
        identifier: entry["identifier"].presence
      )

      if %w[credit_card loan].include?(kind)
        build_credit_account(source, entry)
      end
      source.save!
      create_payment_recurrence(source, entry)
      source
    end

    # The app stores credit-card debt as a NEGATIVE balance so card usage keeps
    # deducting from the available credit (see MoneySource#used_credit). The
    # wizard collects the debt as a positive magnitude ("Deuda actual").
    def starting_balance_for(kind, row)
      raw = row["starting_balance"].presence || row["balance"].presence
      return 0 if raw.blank?

      balance = raw.to_d
      kind == "credit_card" && balance.positive? ? -balance : balance
    end

    # Loans and credit cards have a fixed periodic payment. When the wizard
    # knows the monthly amount, create a recurring expense so the payment
    # shows up month after month without manual entry.
    def create_payment_recurrence(source, row)
      return unless %w[credit_card loan].include?(source.kind)

      amount = row["monthly_payment"].to_d
      return unless amount.positive?

      RecurringTemplate.create!(
        user: @user,
        category: payment_category,
        kind: "expense",
        amount: amount,
        frequency: "monthly",
        description: I18n.t("wizard.recurring.payment_description", name: source.name),
        money_source: source,
        source: "wizard"
      )
    end

    # Recurring payments share one default expense category, created on demand
    # (same pattern as db/seeds.rb).
    def payment_category
      @payment_category ||= Category.find_or_create_by!(
        name: I18n.t("categories.debt_payments"),
        is_default: true,
        category_type: "expense"
      )
    end
  end
end
