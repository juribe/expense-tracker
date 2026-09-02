# frozen_string_literal: true

require "test_helper"

class MoneySourcesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "money_sources_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
  end

  def create_source(name: "My Account", kind: "account", **opts)
    @user.money_sources.create!({ name: name, kind: kind, starting_balance: 0 }.merge(opts))
  end

  test "GET /money_sources renders the index" do
    create_source
    get money_sources_path
    assert_response :success
    assert_select "h1", text: I18n.t("nav.money_sources")
  end

  test "GET /money_sources shows empty state when no sources" do
    get money_sources_path
    assert_response :success
    assert_select "[data-testid]", count: 0
  end

  test "GET /money_sources/cash filters to cash and accounts only" do
    create_source(name: "Checking", kind: "account")
    create_source(name: "Cash", kind: "cash", starting_balance: 500000)
    create_source(name: "Visa", kind: "credit_card")
    get money_sources_cash_path
    assert_response :success
    assert_select "h1", text: I18n.t("money_sources.index.cash_title")
    assert_select "[data-testid='account-card']", count: 2
    assert_select "[data-testid='accounts-summary']", count: 1
    assert_match(/Checking/, response.body)
    assert_match(/Cash/, response.body)
    assert_no_match(/Visa/, response.body)
    assert_match(/500\.000/, response.body)
  end

  test "GET /money_sources/credit_cards filters to credit cards only and renders summary" do
    create_source(name: "Checking", kind: "account")
    source = create_source(name: "Visa", kind: "credit_card", bank: "Bancolombia", starting_balance: -3000000)
    source.build_credit_account(credit_limit: 20000000, card_brand: "visa", card_last_four: "1234",
                                interest_rate: 24.5, interest_rate_type: "effective_annual")
    source.save!
    get money_sources_credit_cards_path
    assert_response :success
    assert_select "h1", text: I18n.t("money_sources.index.credit_cards_title")
    assert_select "[data-testid='credit-card-card']", count: 1
    assert_select "[data-testid='credit-cards-summary']", count: 1
    assert_match(/Visa/, response.body)
    assert_no_match(/Checking/, response.body)
    # Current debt is the primary figure on the card.
    assert_match(/\$3\.000\.000/, response.body)
    # Summary totals: total debt matches the card's current debt.
    assert_match(/\$3\.000\.000/, response.body)
  end

  test "GET /money_sources/loans filters to loans only" do
    create_source(name: "Visa", kind: "credit_card")
    create_source(name: "Car Loan", kind: "loan")
    get money_sources_loans_path
    assert_response :success
    assert_select "h1", text: I18n.t("money_sources.index.loans_title")
    assert_match(/Car Loan/, response.body)
    assert_no_match(/Visa/, response.body)
  end

  test "GET /money_sources/loans renders cards and a summary with correct totals" do
    loan = @user.money_sources.create!(name: "Crédito Hipotecario", kind: "loan", starting_balance: 0, active: true, bank: "Davibank")
    loan.build_credit_account(principal_amount: 170900000, outstanding_balance: 66959723,
                              installment_amount: 1130642, installment_count: 192, installments_paid: 75,
                              interest_rate: 18.05, interest_rate_type: "effective_annual",
                              payment_frequency: "monthly", start_date: "2020-01-15")
    loan.save!

    get money_sources_loans_path
    assert_response :success

    assert_select "[data-testid='loan-card']", count: 1
    assert_select "[data-testid='loans-summary']", count: 1
    # Remaining balance owed is the primary figure.
    assert_match(/66\.959\.723/, response.body)
    # Summary total matches the single card's outstanding balance.
    assert_match(/66\.959\.723/, response.body)
    assert_match(/#{I18n.t("money_sources.loans.summary_total")}/, response.body)
    assert_match(/#{I18n.t("money_sources.loans.repaid", pct: 60.8)}/, response.body)
  end

  test "GET /money_sources/loans shows the empty state without loans" do
    get money_sources_loans_path
    assert_response :success
    assert_select "[data-testid='loan-card']", count: 0
    assert_match(/#{I18n.t("money_sources.index.loans_empty_title")}/, response.body)
  end

  test "GET /money_sources/credit_cards shows empty state" do
    get money_sources_credit_cards_path
    assert_response :success
    assert_select "h1", text: I18n.t("money_sources.index.credit_cards_title")
  end

  test "GET /money_sources shows the resume banner for an in-progress setup" do
    setup = @user.financial_setups.create!(status: "in_progress")
    setup.set_choice("accounts", "skip")
    setup.save!

    get money_sources_path
    assert_response :success
    assert_select "[data-testid='unfinished-setup-banner']", count: 1 do
      assert_select "a[href='#{financial_setup_path}']"
    end
  end

  test "GET /money_sources hides the resume banner for a fresh setup" do
    get money_sources_path
    assert_response :success
    assert_select "[data-testid='unfinished-setup-banner']", count: 0
  end

  test "GET /money_sources/recognition lists sources with unconfigured status and no edit panel" do
    create_source(name: "Mi Cuenta", kind: "account")
    get money_sources_recognition_path
    assert_response :success
    assert_select "h1", text: I18n.t("money_sources.recognition.title")
    assert_select "[data-testid='recognition-row']", count: 1
    assert_select "[data-testid='recognition-status']", text: /#{I18n.t('money_sources.recognition.status_unconfigured')}/
    assert_select "[data-testid='recognition-edit-panel']", count: 0
  end

  test "GET /money_sources/recognition shows configured status and delete action" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    get money_sources_recognition_path
    assert_response :success
    assert_select "[data-testid='recognition-status']", text: /#{I18n.t('money_sources.recognition.status_configured')}/
    assert_select "[data-testid='recognition-row'] form[action='#{money_source_recognition_destroy_path(source.id)}']"
    expected_confirm = "#{I18n.t('money_sources.recognition.delete_confirm_title')} #{I18n.t('money_sources.recognition.delete_confirm_body')}"
    assert_select "[data-testid='recognition-row'] form[data-turbo-confirm='#{expected_confirm}']"
  end

  test "GET /money_sources/recognition?edit opens the edit drawer with chips and suggestions" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"], sender: ["no-reply@davibank.com"])
    get money_sources_recognition_path(edit: source.id)
    assert_response :success
    assert_select "[data-testid='recognition-edit-panel']", count: 1
    assert_select "[data-testid='recognition-edit-panel'].recognition-drawer[role='dialog']"
    assert_select ".recognition-drawer-overlay"
    assert_select "[data-testid='recognition-chip']", count: 2
    assert_select "form[action='#{money_source_recognition_path(source.id)}'][method='post']"
    assert_select "form.recognition-form[data-unsaved-message='#{I18n.t('money_sources.recognition.unsaved_changes')}']"
    assert_select "[data-testid='recognition-drawer-foot'] [data-testid='recognition-save']"
    assert_select "[data-recognition-dismiss-suggestions]"
    assert_select ".recognition-suggestions-actions [data-recognition-accept-suggestions]"
    assert_select "[data-testid='last-four-hint']", count: 1
  end

  test "GET /money_sources/recognition?edit hides the last-four hint when digits exist" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank", identifier: "5678")
    get money_sources_recognition_path(edit: source.id)
    assert_response :success
    assert_select "[data-testid='last-four-hint']", count: 0
    assert_select ".recognition-chip-suggested[data-suggested-value='5678']"
  end

  test "GET /money_sources/recognition without edit renders no drawer" do
    create_source(name: "Davibank", kind: "account", bank: "Davibank")
    get money_sources_recognition_path
    assert_response :success
    assert_select ".recognition-drawer", count: 0
    assert_select ".recognition-drawer-overlay", count: 0
  end

  test "PATCH /money_sources/recognition/:id adds and removes identifiers per kind" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"], sender: ["no-reply@davibank.com"])

    patch money_source_recognition_path(source.id),
          params: { keywords: ["davi", "origen"], senders: ["factura@davibank.com", "davibank.com"], subjects: ["Movimiento"] }

    assert_redirected_to money_sources_recognition_path
    source.reload
    ids = source.recognition.recognition_identifiers
    assert_equal %w[davi origen], ids.select(&:keyword?).map(&:value).sort
    assert_equal ["factura@davibank.com"], ids.select(&:sender?).map(&:value)
    assert_equal ["davibank.com"], ids.select(&:domain?).map(&:value)
    assert_equal ["Movimiento"], ids.select(&:subject?).map(&:value)
  end

  test "PATCH /money_sources/recognition/:id with all-empty values destroys recognition" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    assert source.recognition_configured?

    patch money_source_recognition_path(source.id), params: { keywords: [], senders: [], subjects: [] }

    assert_redirected_to money_sources_recognition_path
    source.reload
    assert_not source.recognition_configured?
    assert_nil source.recognition
    assert source.reload.persisted?, "delete must not destroy the money source"
  end

  test "DELETE /money_sources/recognition/:id removes recognition but keeps the source" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    source_id = source.id

    delete money_source_recognition_destroy_path(source.id)

    assert_redirected_to money_sources_recognition_path
    source = MoneySource.find(source_id)
    assert source.persisted?
    assert_not source.recognition_configured?
    assert_nil source.recognition
  end

  test "GET /money_sources/new renders the form" do
    get new_money_source_path
    assert_response :success
    assert_select "form"
  end

  test "POST /money_sources creates a money source" do
    assert_difference "MoneySource.count", 1 do
      post money_sources_path, params: {
        money_source: { name: "New Account", kind: "account", starting_balance: 500 }
      }
    end
    assert_redirected_to money_sources_cash_path
    follow_redirect!
    assert_equal I18n.t("money_sources.flashes.created"), flash[:notice]
  end

  test "POST /money_sources creates a credit card" do
    assert_difference "MoneySource.count", 1 do
      post money_sources_path, params: {
        money_source: { name: "Visa", kind: "credit_card" }
      }
    end
    assert_redirected_to money_sources_credit_cards_path
  end

  test "POST /money_sources renders new on validation failure" do
    post money_sources_path, params: {
      money_source: { name: "", kind: "account" }
    }
    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "GET /money_sources/:id renders show" do
    source = create_source
    get money_source_path(source)
    assert_response :success
  end

  test "GET /money_sources/:id/edit renders edit form" do
    source = create_source
    get edit_money_source_path(source)
    assert_response :success
    assert_select "form"
  end

  test "PATCH /money_sources/:id updates the money source" do
    source = create_source
    patch money_source_path(source), params: {
      money_source: { name: "Updated Name" }
    }
    assert_redirected_to money_sources_cash_path
    assert_equal "Updated Name", source.reload.name
  end

  test "DELETE /money_sources/:id destroys the money source" do
    source = create_source
    assert_difference "MoneySource.count", -1 do
      delete money_source_path(source)
    end
    assert_redirected_to money_sources_cash_path
  end

  test "user cannot access other user's money source" do
    other_user = User.create!(name: "Other", email: "other_money_src_ctrl@example.com", password: "password123")
    other_source = other_user.money_sources.create!(name: "Other Source", kind: "account")
    get money_source_path(other_source)
    assert_response :not_found
  end

  test "POST /money_sources creates a credit card with credit_account" do
    assert_difference "MoneySource.count", 1 do
      assert_difference "CreditAccount.count", 1 do
        post money_sources_path, params: {
          money_source: {
            name: "Visa", kind: "credit_card", bank: "Bancolombia",
            credit_account_attributes: {
              credit_limit: "20000000", card_brand: "visa", card_last_four: "1234",
              interest_rate: "24.5", interest_rate_type: "effective_annual",
              statement_day: "15", payment_due_day: "30"
            }
          }
        }
      end
    end
    assert_redirected_to money_sources_credit_cards_path
    source = MoneySource.last
    assert_equal "credit_card", source.kind
    assert_equal "Bancolombia", source.bank
    assert_equal BigDecimal("20000000"), source.credit_account.credit_limit
    assert_equal "1234", source.credit_account.card_last_four
  end

  test "POST /money_sources accepts Colombian-formatted decimals" do
    post money_sources_path, params: {
      money_source: {
        name: "Visa", kind: "credit_card", bank: "Bancolombia", starting_balance: "1.234.567,89",
        credit_account_attributes: {
          credit_limit: "20.000.000", card_brand: "visa", card_last_four: "1234",
          interest_rate: "29,3", interest_rate_type: "effective_annual"
        }
      }
    }
    assert_redirected_to money_sources_credit_cards_path
    source = MoneySource.last
    assert_equal BigDecimal("1234567.89"), source.starting_balance
    assert_equal BigDecimal("20000000"), source.credit_account.credit_limit
    assert_equal BigDecimal("29.3"), source.credit_account.interest_rate
  end

  test "POST /money_sources creates a loan with credit_account" do
    assert_difference "MoneySource.count", 1 do
      assert_difference "CreditAccount.count", 1 do
        post money_sources_path, params: {
          money_source: {
            name: "Car Loan", kind: "loan", bank: "Banco",
            credit_account_attributes: {
              principal_amount: "114000000", outstanding_balance: "95000000",
              interest_rate: "21.27", interest_rate_type: "effective_annual",
              installment_count: "72", installment_amount: "2686800",
              payment_frequency: "monthly", start_date: "2024-01-01", end_date: "2030-01-01"
            }
          }
        }
      end
    end
    assert_redirected_to money_sources_loans_path
    source = MoneySource.last
    assert_equal "loan", source.kind
    assert_equal BigDecimal("114000000"), source.credit_account.principal_amount
    assert_equal "monthly", source.credit_account.payment_frequency
  end

  test "POST /money_sources does not create credit_account for account kind" do
    assert_difference "MoneySource.count", 1 do
      assert_difference "CreditAccount.count", 0 do
        post money_sources_path, params: {
          money_source: { name: "Checking", kind: "account", starting_balance: "1000" }
        }
      end
    end
  end

  test "GET index groups debt sources" do
    create_source(name: "Checking", kind: "account")
    create_source(name: "Visa", kind: "credit_card")
    get money_sources_path
    assert_response :success
    assert_select "h1", text: I18n.t("nav.money_sources")
  end

  test "GET show renders debt panel for a credit card" do
    source = create_source(name: "Visa", kind: "credit_card", bank: "Bancolombia")
    source.build_credit_account(credit_limit: 20000000, card_brand: "visa", card_last_four: "1234")
    source.save!
    get money_source_path(source)
    assert_response :success
    assert_select ".card-debt"
  end

  test "GET show renders debt panel for a loan" do
    source = create_source(name: "Car Loan", kind: "loan", bank: "Banco")
    source.build_credit_account(principal_amount: 114000000, outstanding_balance: 95000000,
                                installment_count: 72, installment_amount: 2686800,
                                payment_frequency: "monthly")
    source.save!
    get money_source_path(source)
    assert_response :success
    assert_select ".card-debt"
  end

  test "GET show renders loan outstanding balance, not zero" do
    source = create_source(name: "Car Loan", kind: "loan", bank: "Banco")
    source.build_credit_account(principal_amount: 114000000, outstanding_balance: 95000000,
                                installment_count: 72, installment_amount: 2686800,
                                payment_frequency: "monthly")
    source.save!
    get money_source_path(source)
    assert_response :success
    assert_match(/\$95\.000\.000/, response.body)
  end

  test "GET index renders a loan card without error" do
    source = create_source(name: "Car Loan", kind: "loan", bank: "Banco")
    source.build_credit_account(principal_amount: 114000000, outstanding_balance: 95000000,
                                installment_count: 72, installment_amount: 2686800,
                                payment_frequency: "monthly", interest_rate: 21.27,
                                interest_rate_type: "effective_annual")
    source.save!
    get money_sources_path
    assert_response :success
    assert_match(/Car Loan/, response.body)
  end

  test "GET new renders kind panels" do
    get new_money_source_path
    assert_response :success
    assert_select "[data-kind-panel]"
  end

  test "GET edit renders form with existing credit account" do
    source = create_source(name: "Visa", kind: "credit_card")
    source.build_credit_account(credit_limit: 20000000, card_brand: "visa", card_last_four: "1234")
    source.save!
    get edit_money_source_path(source)
    assert_response :success
    assert_select "select[name='money_source[credit_account_attributes][card_brand]']"
  end

  test "PATCH updates credit_account through nested attributes" do
    source = create_source(name: "Visa", kind: "credit_card")
    source.build_credit_account(credit_limit: 1000000, card_last_four: "1111")
    source.save!

    patch money_source_path(source), params: {
      money_source: {
        name: source.name, kind: "credit_card",
        credit_account_attributes: {
          id: source.credit_account.id,
          credit_limit: "2000000", card_last_four: "2222"
        }
      }
    }
    assert_redirected_to money_sources_credit_cards_path
    source.reload
    assert_equal BigDecimal("2000000"), source.credit_account.credit_limit
    assert_equal "2222", source.credit_account.card_last_four
  end
end
