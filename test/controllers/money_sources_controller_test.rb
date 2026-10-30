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

  test "GET /money_sources/:id shows the manual adjustment trace on a loan" do
    loan = create_source(name: "Crédito carro", kind: "loan")
    loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)
    Reconciliation::CheckBalance.call(user: @user, money_source: loan, actual_balance: "30.500.000",
                                      adjust: true, note: "Saldo del banco")

    get money_source_path(loan)

    assert_response :success
    assert_select "dt", text: I18n.t("money_sources.show.manual_adjustment")
    assert_select "dd", text: /Saldo del banco/
  end

  test "GET /money_sources redirects to the accounts section" do
    create_source

    get money_sources_path

    assert_redirected_to money_sources_cash_path
  end

  test "GET /money_sources with an unknown type redirects to the accounts section" do
    create_source

    get money_sources_path(type: "bogus")

    assert_redirected_to money_sources_cash_path
  end

  test "GET /money_sources/cash warns when a source balance is negative" do
    source = create_source(name: "Ahorros", kind: "account", starting_balance: 0)
    source.update_column(:cached_balance, -25_000)

    get money_sources_cash_path

    assert_response :success
    assert_select "[data-testid=negative-balance-warning]", count: 1
  end

  test "GET /money_sources/cash does not warn for positive balances or debt sources" do
    create_source(name: "Ahorros", kind: "account", starting_balance: 50_000)
    create_source(name: "Visa", kind: "credit_card", starting_balance: -3_000_000)

    get money_sources_cash_path

    assert_response :success
    assert_select "[data-testid=negative-balance-warning]", count: 0
  end

  test "GET /money_sources/pockets renders the pockets page with only pockets" do
    pocket = create_source(name: "Bolsillo Europa", kind: "pocket")
    create_source(name: "Davibank", kind: "account")

    get money_sources_pockets_path
    assert_response :success
    assert_select "a[href=?]", money_source_path(pocket)
    assert_select "h5.card-title", text: /Davibank/, count: 0
  end

  # Payments apply to every credit: credit cards AND all loan subtypes.
  test "GET /money_sources shows a payments button on every debt source card" do
    create_source(name: "Checking", kind: "account")
    create_source(name: "Cash", kind: "cash", starting_balance: 500000)
    create_source(name: "Visa", kind: "credit_card", starting_balance: -3000000)
    create_source(name: "Car Loan", kind: "loan", sub_kind: "vehicle", starting_balance: -2000000)
    create_source(name: "Mortgage", kind: "loan", sub_kind: "mortgage", starting_balance: -50000000)

    get money_sources_credit_cards_path
    assert_select "a span", text: I18n.t("payments.index_button"), count: 1

    get money_sources_loans_path
    # Both loans carry the button; the cards and accounts do not.
    assert_select "a span", text: I18n.t("payments.index_button"), count: 2
  end

  test "GET /money_sources/loans offers the savings tool on each loan card" do
    loan = create_source(name: "Car Loan", kind: "loan", sub_kind: "vehicle", starting_balance: -2000000)

    get money_sources_loans_path

    assert_response :success
    assert_select "a[href=?]", money_source_credits_path(loan)
  end

  test "GET /money_sources/credit_cards offers the savings tool on each card" do
    card = create_source(name: "Visa", kind: "credit_card", starting_balance: -3000000)

    get money_sources_credit_cards_path

    assert_response :success
    assert_select "a[href=?]", money_source_credits_path(card)
  end

  test "GET /money_sources/:id shows the savings tool on a credit card detail" do
    card = create_source(name: "Visa", kind: "credit_card", starting_balance: -3000000)

    get money_source_path(card)

    assert_response :success
    assert_select "a[href=?]", money_source_credits_path(card)
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

  test "GET /money_sources/credit_cards links Nueva tarjeta de crédito to the credit card form" do
    get money_sources_credit_cards_path

    assert_response :success
    assert_select "a[href=?]", new_money_source_path(kind: "credit_card"), text: /Nueva tarjeta de crédito/
  end

  test "GET /money_sources/loans links Nuevo préstamo to the loan form" do
    get money_sources_loans_path

    assert_response :success
    assert_select "a[href=?]", new_money_source_path(kind: "loan"), text: /Nuevo préstamo/
  end

  test "GET /money_sources/pockets links Nuevo bolsillo to the pocket form" do
    get money_sources_pockets_path

    assert_response :success
    assert_select "a[href=?]", new_money_source_path(kind: "pocket"), text: /Nuevo bolsillo/
  end

  test "GET /money_sources/cash offers a new-source menu for every cash-like kind" do
    get money_sources_cash_path

    assert_response :success
    %w[account debit_card cash wallet].each do |kind|
      assert_select "a[href=?]", new_money_source_path(kind: kind),
                    text: /#{I18n.t("money_sources.form.new_titles.#{kind}")}/
    end
    assert_select "a[href=?]", new_money_source_path(kind: "credit_card"), count: 0
  end

  test "GET /money_sources/cash shows the resume banner for an in-progress setup" do
    setup = @user.financial_setups.create!(status: "in_progress")
    setup.set_choice("accounts", "skip")
    setup.save!

    get money_sources_cash_path
    assert_response :success
    assert_select "[data-testid='unfinished-setup-banner']", count: 1 do
      assert_select "a[href='#{financial_setup_path}']"
    end
  end

  test "GET /money_sources/cash hides the resume banner for a fresh setup" do
    get money_sources_cash_path
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
    sibling = create_source(name: "Davibank Clásica", kind: "account", bank: "Davibank")
    sibling.ensure_recognition.replace_identifiers(sender: ["notificaciones@davibank.com"], subject: ["Transacción aprobada"])
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"], sender: ["no-reply@davibank.com"])
    get money_sources_recognition_path(edit: source.id)
    assert_response :success
    # PRODUCT drawer: keywords only (the bank-level signals live in the
    # bank drawer of the group).
    assert_select "[data-testid='recognition-edit-panel'][data-testid-mode='source']", count: 1
    assert_select "[data-testid='recognition-edit-panel'].recognition-drawer[role='dialog']"
    assert_select ".recognition-drawer-overlay"
    assert_select "[data-testid='recognition-chip']", count: 1
    assert_select "form[action='#{money_source_recognition_path(source.id)}'][method='post']"
    assert_select "form.recognition-form[data-unsaved-message='#{I18n.t('money_sources.recognition.unsaved_changes')}']"
    assert_select "[data-testid='recognition-drawer-foot'] [data-testid='recognition-save']"
    assert_select "[data-testid='last-four-hint']", count: 1
  end

  test "GET /money_sources/recognition?edit renders per-section confirmed and suggested chips" do
    sibling = create_source(name: "Davibank Clásica", kind: "account", bank: "Davibank")
    sibling.ensure_recognition.replace_identifiers(sender: ["notificaciones@davibank.com"], subject: ["Transacción aprobada"])
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    source.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "sender", value: "nuevo@davibank.com", status: "suggested", origin: "gmail", observation_count: 2
    )

    get money_sources_recognition_path(edit: source.id)

    assert_response :success
    # PRODUCT drawer: the keywords section only; senders/subjects belong to
    # the group's bank drawer. The suggested keyword comes from the shared
    # institution token (the "davibank" name token is ambiguous here: two of
    # the user's source names share it).
    assert_select "[data-recognition-chips='senders'] [data-testid='recognition-chip']", count: 0
    assert_select "[data-recognition-chips='subjects'] [data-testid='recognition-chip']", count: 0
    assert_select "[data-testid='recognition-suggested-block']", count: 1
    assert_select ".recognition-chip-suggested[data-suggested-for='keywords'][data-suggested-value='davibank']"
    assert_select ".recognition-chip-suggested .recognition-chip-provenance",
                  text: I18n.t("money_sources.recognition.suggested_from_institution")
  end

  test "cash sources group as 'Efectivo' without any bank configuration affordance" do
    create_source(name: "Efectivo", kind: "cash", bank: "")
    create_source(name: "Davibank", kind: "account", bank: "Davibank")

    get money_sources_recognition_path
    assert_response :success

    assert_select "[data-testid=recognition-bank-group]" do |groups|
      assert_select groups, "[data-testid='recognition-bank-edit']", count: 1
    end
    assert_select ".recognition-bank-name", text: I18n.t("money_sources.recognition.cash_group")
    assert_select ".recognition-bank-name", text: I18n.t("money_sources.recognition.no_bank_group"), count: 0
  end

  test "GET /money_sources/recognition?bank_edit opens the bank drawer of the group with suggestions" do
    sibling = create_source(name: "Davibank Clásica", kind: "account", bank: "Davibank")
    sibling.ensure_recognition.replace_identifiers(sender: [ "notificaciones@davibank.com" ], subject: [ "Transacción aprobada" ])
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "sender", value: "nuevo@davibank.com", status: "suggested", origin: "gmail", observation_count: 2
    )

    get money_sources_recognition_path(bank_edit: "legacy:davibank")
    assert_response :success
    # The seed (earliest member: the sibling) carries the group's bank config.
    assert_select "[data-testid='recognition-edit-panel'][data-testid-mode='bank']", count: 1
    assert_select "[data-testid='recognition-chip']", count: 2
    assert_select ".recognition-chip-suggested[data-suggested-for='senders'][data-suggested-value='nuevo@davibank.com']"
    assert_select "form[action='#{money_source_recognition_path(sibling.id)}']"
  end

  test "suggestions a member discovers surface in the BANK drawer and are swept on save" do
    sibling = create_source(name: "Davibank Seed", kind: "account", bank: "Davibank")
    member = create_source(name: "Davibank Member", kind: "account", bank: "Davibank")
    member.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "sender", value: "mail@procesador.co", status: "suggested", origin: "gmail", observation_count: 3
    )

    # The member's pending BANK-level suggestion is listed in the SEED's
    # bank drawer (earliest source of the group = the sibling).
    get money_sources_recognition_path(bank_edit: "legacy:davibank")
    assert_response :success
    assert_select ".recognition-chip-suggested[data-suggested-for='senders'][data-suggested-value='mail@procesador.co']"

    # Review once: the user DISMISSES the value and saves.
    patch money_source_recognition_path(sibling.id), params: {
      senders: [], subjects: [], dismissed: { "senders" => [ "mail@procesador.co" ] }
    }
    assert_redirected_to money_sources_recognition_path

    member.reload
    assert_empty member.recognition_identifiers.suggested
    assert_nil member.reload.recognition # nothing left → record dropped
  end

  test "GET /money_sources/recognition shows pending review for configured sources with suggestions" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.replace_identifiers(keyword: ["davi"])
    source.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "keyword", value: "nuevo", status: "suggested", origin: "gmail"
    )

    get money_sources_recognition_path

    assert_select "[data-testid='recognition-status']", text: /#{I18n.t('money_sources.recognition.status_pending')}/
    assert_select "[data-testid='recognition-row-pending-count']",
                  text: I18n.t("money_sources.recognition.source_pending", count: 1)
    assert_select "[data-testid='recognition-suggestion-count']",
                  text: I18n.t("money_sources.recognition.group_pending", count: 1)
  end

  # --- Own suggestions: persisted, counted, dismissible ----------------------

  test "GET /money_sources/recognition?edit persists the source's own suggestions and counts them on the bank card" do
    source = create_source(name: "Ahorros Banco de Bogotá", kind: "account", bank: "Banco de Bogotá")

    get money_sources_recognition_path(edit: source.id)
    assert_response :success

    source.reload
    pending_ids = source.recognition.recognition_identifiers.suggested
    assert pending_ids.any?, "the engine's own suggestions persist as suggested rows"

    get money_sources_recognition_path
    assert_select "[data-testid='recognition-suggestion-count']",
                  text: I18n.t("money_sources.recognition.group_pending", count: pending_ids.count)
  end

  test "dismissed own suggestions stop counting and never resurface" do
    source = create_source(name: "Ahorros Banco de Bogotá", kind: "account", bank: "Banco de Bogotá")
    get money_sources_recognition_path(edit: source.id)
    total = source.reload.recognition.recognition_identifiers.suggested.count
    assert total.positive?
    value = source.recognition.recognition_identifiers.suggested.first.value

    patch money_source_recognition_path(source.id), params: { keywords: [], senders: [], subjects: [],
                                                              dismissed: { "keywords" => [value] } }
    assert_redirected_to money_sources_recognition_path
    assert source.reload.recognition.recognition_identifiers.exists?(kind: "keyword", value: value, status: "dismissed")

    get money_sources_recognition_path(edit: source.id)
    assert_response :success
    remaining = source.reload.recognition.recognition_identifiers.suggested
    assert_not remaining.exists?(value: value)
    assert_select "[data-testid='recognition-suggested-chip'][data-suggested-value='#{value}']", count: 0
    assert_select "[data-testid='recognition-suggestion-count']",
                  text: I18n.t("money_sources.recognition.group_pending", count: remaining.count)
  end

  test "typing a previously dismissed value confirms it instead of leaving a tombstone" do
    source = create_source(name: "Ahorros Banco de Bogotá", kind: "account", bank: "Banco de Bogotá")
    get money_sources_recognition_path(edit: source.id)
    value = source.reload.recognition.recognition_identifiers.suggested.find { |id| id.keyword? }.value
    patch money_source_recognition_path(source.id), params: { keywords: [], senders: [], subjects: [],
                                                              dismissed: { "keywords" => [value] } }

    patch money_source_recognition_path(source.id), params: { keywords: [value], senders: [], subjects: [] }

    identifiers = source.reload.recognition.recognition_identifiers.where(kind: "keyword")
    identifiers.select { |id| id.value == value }.each do |id|
      assert id.confirmed?
      assert_equal "user", id.origin
    end
    assert identifiers.count { |id| id.value == value } > 0
    assert_not identifiers.any? { |id| id.value == value && (id.suggested? || id.dismissed?) }
  end

  test "GET /money_sources/recognition wires the how-it-works guided tutorial" do
    create_source(name: "Davibank", kind: "account", bank: "Davibank")

    get money_sources_recognition_path
    assert_response :success
    btn = css_select("[data-testid='recognition-help-btn']").first
    assert btn
    assert_equal "#recognition-help-modal", btn["data-bs-target"]
    assert_equal "modal", btn["data-bs-toggle"]

    assert_select "[data-testid='recognition-help-modal'][aria-hidden='true']"
    assert_select "[data-testid='recognition-help-modal'] h2", text: I18n.t("money_sources.recognition.help_title")
    # Guided assistant: five steps, clickable progress, prev/next controls.
    assert_select "[data-testid='recognition-help-step']", count: 6
    assert_select "[data-testid='recognition-help-step'][data-help-active='true']", count: 1
    assert_select "[data-testid='help-progress-step']", count: 6
    assert_select "[data-testid='help-prev']"
    assert_select "[data-testid='help-next']"
    assert_select "[data-testid='help-restart']", count: 1
    # Same demo text on both channels (WhatsApp message == app text input):
    # the shared paragraph with the highlighted money-source phrase renders twice.
    rendered_text = /con mi <mark class="recognition-help-mark">tarjeta oro<\/mark>\./
    assert response.body.scan(rendered_text).size >= 2, "WhatsApp and app-text demos must share the same sentence"
    # The email of step 1 highlights the matched money source too.
    assert response.body.scan("recognition-help-mark").size >= 3
    assert_select "[data-testid='help-next']", text: I18n.t("money_sources.recognition.help_next")
  end

  # --- Collapsible bank cards: collapses, default icons, chips, footer -------------------

  test "GET /money_sources/recognition renders bank cards collapsed by default and expands only the edited group" do
    davibank = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    create_source(name: "Ahorros Nu", kind: "account", bank: "Bancolombia")

    get money_sources_recognition_path
    assert_response :success
    assert_select "[data-testid='recognition-bank-group']", count: 2
    assert_select "[data-testid='recognition-bank-group'].expanded", count: 0
    assert_select "[data-testid='recognition-bank-group'] [data-testid='recognition-bank-toggle'][aria-expanded='false']",
                  count: 2

    get money_sources_recognition_path(edit: davibank.id)
    assert_select "[data-testid='recognition-bank-group'].expanded", count: 1
    assert_select "[data-testid='recognition-bank-group'] [data-testid='recognition-bank-toggle'][aria-expanded='true']",
                  count: 1

    get money_sources_recognition_path(bank_edit: "legacy:davibank")
    assert_select "[data-testid='recognition-bank-group'].expanded", count: 1
  end

  test "GET /money_sources/recognition renders default bank icons instead of images" do
    create_source(name: "Davibank", kind: "account", bank: "Davibank")

    get money_sources_recognition_path
    assert_response :success
    assert_select "[data-testid='recognition-bank-group'] .recognition-bank-icon i.ti-building-bank", count: 1
    assert_select "[data-testid='recognition-bank-group'] img", count: 0
  end

  test "GET /money_sources/recognition renders the banks section header without an add-bank affordance" do
    create_source(name: "Davibank", kind: "account", bank: "Davibank")

    get money_sources_recognition_path
    assert_response :success
    assert_select "h2", text: I18n.t("money_sources.recognition.banks_title")
    assert_select "p", text: I18n.t("money_sources.recognition.banks_subtitle")
    assert_no_match(/Agregar banco/, response.body)
  end

  test "GET /money_sources/recognition shows identifiers per source" do
    source = create_source(name: "Tarjeta Infinite", kind: "credit_card", bank: "Davibank", identifier: "6017")
    source.ensure_recognition.replace_identifiers(keyword: ["infinite"])

    get money_sources_recognition_path
    assert_response :success

    assert_select ".recognition-table th", text: I18n.t("money_sources.recognition.col_identifiers")
    assert_select ".recognition-table th", text: "Palabras clave", count: 0
    assert_select "[data-testid='recognition-row'] [data-testid='recognition-identifiers']",
                  text: "infinite, •••• 6017"
  end

  # Cards whose identifier is blank resolve the last four from the child
  # credit_account — loaded per kind in the controller, never as an eager
  # include (it would be unused for cards that carry their own identifier).
  test "GET /money_sources/recognition resolves the last four of identifier-less cards from their credit account" do
    source = create_source(name: "Tarjeta LifeMiles", kind: "credit_card", bank: "Davibank")
    source.build_credit_account(card_last_four: "5986", credit_limit: 3000000, interest_rate: 24.0,
                                interest_rate_type: "effective_annual")
    source.save!
    source.ensure_recognition.replace_identifiers(keyword: ["lifemiles"])

    get money_sources_recognition_path
    assert_response :success

    assert_select "[data-testid='recognition-row'] [data-testid='recognition-identifiers']",
                  text: "lifemiles, •••• 5986"
  end

  test "GET /money_sources/recognition footer links to a new source and to the bank suggestion review" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    source.ensure_recognition.tap(&:save!).recognition_identifiers.create!(
      kind: "keyword", value: "millas", status: "suggested", origin: "gmail"
    )

    get money_sources_recognition_path
    assert_response :success

    assert_select "a[data-testid='recognition-add-source'][href='#{new_money_source_path}']"
    assert_select "a[data-testid='recognition-view-suggestions'][href='#{money_sources_recognition_path(bank_edit: 'legacy:davibank')}']",
                  text: I18n.t("money_sources.recognition.view_pending", count: 1)
  end

  test "GET /money_sources/recognition shows bank header status badges" do
    create_source(name: "Davibank", kind: "account", bank: "Davibank").ensure_recognition.replace_identifiers(keyword: ["davi"])
    create_source(name: "Ahorros Nu", kind: "account", bank: "Bancolombia")

    get money_sources_recognition_path
    assert_response :success
    assert_select "[data-testid='recognition-bank-status']",
                  count: 2
    assert_select "[data-testid='recognition-bank-status'].recognition-status-ok",
                  text: I18n.t("money_sources.recognition.group_configured")
    assert_select "[data-testid='recognition-bank-status'].recognition-status-unconfigured",
                  text: I18n.t("money_sources.recognition.status_unconfigured")
  end

  # --- Gmail criteria card ---------------------------------------------------

  test "GET /money_sources/recognition does not render the gmail criteria card without a connection" do
    get money_sources_recognition_path
    assert_select "[data-testid='gmail-criteria-card']", count: 0
  end

  test "GET /money_sources/recognition renders the gmail criteria card as a collapsed summary" do
    GmailConnection.create!(user: @user, email: "me@gmail.com",
                            search_config: { senders: [ "manual@bank.com" ],
                                             domains: [ "bank.com" ],
                                             subject_keywords: [ "pago" ] })

    get money_sources_recognition_path

    assert_select "[data-testid='gmail-criteria-card']", count: 1
    assert_select "[data-testid='gmail-criteria-card'].expanded", count: 0
    assert_select "[data-testid='gmail-connected']", text: I18n.t("money_sources.recognition.gmail_connected")
    assert_select "[data-testid='gmail-criteria-manage']",
                  text: I18n.t("money_sources.recognition.criteria_manage")
    form = css_select("form[action='#{gmail_connection_path}']")
    assert_equal 1, form.size
    assert_select form, "textarea[name='search_config[senders]']", text: "manual@bank.com"
    assert_select form, "textarea[name='search_config[domains]']", text: "bank.com"
    assert_select form, "textarea[name='search_config[subject_keywords]']", text: "pago"
    assert_select "[data-testid='gmail-criteria-rescan']", count: 1
  end

  test "GET /money_sources/recognition prefills the gmail criteria card from the scan suggestions" do
    GmailConnection.create!(user: @user, email: "me@gmail.com").update!(setup_suggestions: {
      "scanned" => 10, "passed" => 2,
      "senders" => [ { "value" => "notificaciones@davibank.com", "count" => 2 },
                     { "value" => "otro@davibank.com", "count" => 3 } ],
      "domains" => [ { "value" => "davibank.com", "count" => 2 } ],
      "subject_keywords" => [ { "value" => "transacción", "count" => 1 } ],
      "subject_templates" => [ { "value" => "Transacción aprobada por", "count" => 2,
                                 "institution" => "DAVIbank" } ]
    })

    get money_sources_recognition_path

    assert_select "[data-testid='gmail-criteria-card']", count: 1
    form = css_select("form[action='#{gmail_connection_path}']")
    assert_select form, "textarea[name='search_config[senders]']",
                  text: "notificaciones@davibank.com, otro@davibank.com"
    assert_select form, "textarea[name='search_config[subject_keywords]']",
                  text: "transacción, Transacción aprobada por"
    # Suggestion provenance (value + occurrence count) is visible for review.
    assert_select "[data-testid='gmail-criteria-entry']", count: 5
    assert_match(/Transacción aprobada por \(2 · DAVIbank\)/, response.body)
  end

  test "GET /money_sources/recognition keeps the rescan button outside the criteria form" do
    connection = GmailConnection.create!(user: @user, email: "me@gmail.com")
    connection.update!(setup_suggestions: { "passed" => 1, "senders" => [ { "value" => "a@b.com", "count" => 2 } ] })

    get money_sources_recognition_path

    assert_response :success
    # A nested <form> corrupts the outer form's authenticity_token.
    assert_select "form form", count: 0
    # While the scan runs in the background the JS auto-refresh needs the
    # status endpoint; the page reloads itself when the scan finishes.
    assert_select "[data-testid='gmail-criteria-rescan'] [data-sync-status-path]"
  end

  test "GET /money_sources/recognition marks the criteria card as syncing and expanded" do
    connection = GmailConnection.create!(user: @user, email: "me@gmail.com")
    connection.update!(syncing: Time.current)

    get money_sources_recognition_path

    assert_select "[data-testid='gmail-criteria-card'][data-sync-in-progress].expanded", count: 1
    assert_select "[data-testid='criteria-syncing']",
                  text: I18n.t("money_sources.recognition.criteria_syncing")
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

  test "GET /money_sources/recognition lists only payment sources (loans and pockets excluded)" do
    create_source(name: "Mi Cuenta", kind: "account")
    create_source(name: "Crédito Libre", kind: "loan", sub_kind: "personal")
    create_source(name: "Bolsillo Viaje", kind: "pocket")
    get money_sources_recognition_path
    assert_response :success
    assert_select "[data-testid='recognition-row']", count: 1
    assert_select "[data-testid='recognition-row'] .recognition-row-name", text: "Mi Cuenta"
  end

  test "PATCH /money_sources/recognition/:id rejects a non-payment source" do
    loan = create_source(name: "Crédito Libre", kind: "loan", sub_kind: "personal")

    patch money_source_recognition_path(loan.id), params: { keywords: ["credito"], senders: [], subjects: [] }

    assert_response :not_found
    loan.reload
    assert_nil loan.recognition
    assert_not loan.recognition_configured?
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

  test "PATCH /money_sources/recognition/:id promotes accepted suggestions without duplicating them" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.recognition_identifiers.create!(
      kind: "sender", value: "nuevo@davibank.com", status: "suggested", origin: "gmail", observation_count: 3
    )
    recognition.replace_identifiers(keyword: ["davi"])

    patch money_source_recognition_path(source.id),
          params: { keywords: ["davi"], senders: ["nuevo@davibank.com"], subjects: [] }

    source.reload
    senders = source.recognition_identifiers.where(kind: "sender")
    assert_equal 1, senders.count
    assert senders.first.confirmed?
    assert source.recognition_configured?
  end

  test "PATCH /money_sources/recognition/:id tombstones dismissed suggestions and preserves untouched ones" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.replace_identifiers(keyword: ["davi"])
    recognition.recognition_identifiers.create!(kind: "sender", value: "descartado@davibank.com", status: "suggested", origin: "gmail")
    recognition.recognition_identifiers.create!(kind: "sender", value: "pendiente@davibank.com", status: "suggested", origin: "gmail")

    patch money_source_recognition_path(source.id),
          params: {
            keywords: ["davi"], senders: [], subjects: [],
            dismissed: { senders: ["descartado@davibank.com"] }
          }

    source.reload
    dismissed = source.recognition.recognition_identifiers.find_by(kind: "sender", value: "descartado@davibank.com")
    assert dismissed.dismissed?
    assert source.recognition.recognition_identifiers.exists?(kind: "sender", value: "pendiente@davibank.com", status: "suggested")
  end

  test "PATCH /money_sources/recognition/:id with all-empty keeps untouched suggestions and record" do
    source = create_source(name: "Davibank", kind: "account", bank: "Davibank")
    recognition = source.ensure_recognition.tap(&:save!)
    recognition.replace_identifiers(keyword: ["davi"])
    recognition.recognition_identifiers.create!(kind: "sender", value: "nuevo@davibank.com", status: "suggested", origin: "gmail")

    patch money_source_recognition_path(source.id), params: { keywords: [], senders: [], subjects: [] }

    assert_redirected_to money_sources_recognition_path
    source.reload
    assert_not source.recognition_configured?
    assert source.recognition.present?
    assert source.recognition.recognition_identifiers.exists?(kind: "sender", value: "nuevo@davibank.com")
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

  test "GET /money_sources/new for a loan uses the loan wording in the title and submit button" do
    get new_money_source_path(kind: "loan")

    assert_response :success
    assert_select "h4", text: "Nuevo préstamo"
    assert_select "input[type=submit][value='Guardar préstamo']"
  end

  test "GET /money_sources/new for a credit card preselects the kind and hides the selector" do
    get new_money_source_path(kind: "credit_card")

    assert_response :success
    assert_select "h4", text: "Nueva tarjeta de crédito"
    assert_select "input[type=submit][value='Guardar tarjeta de crédito']"
    assert_select "input[type=hidden][name='money_source[kind]'][value='credit_card']"
    assert_select "select#money_source_kind", count: 0
  end

  test "GET /money_sources/new for a loan labels the dates as first and last payment" do
    get new_money_source_path(kind: "loan")

    assert_response :success
    assert_select "label[for=money_source_credit_account_attributes_start_date]", text: "Fecha del primer pago"
    assert_select "label[for=money_source_credit_account_attributes_end_date]", text: "Fecha del último pago"
  end

  test "GET /money_sources/new uses a name placeholder per kind" do
    {
      "account" => "p. ej. Cuenta ahorro Davivienda",
      "debit_card" => "p. ej. Tarjeta débito Davivienda",
      "credit_card" => "p. ej. Tarjeta Gold",
      "cash" => "p. ej. Efectivo",
      "wallet" => "p. ej. Nequi",
      "pocket" => "p. ej. Viaje a Cartagena",
      "loan" => "p. ej. Préstamo libre inversión"
    }.each do |kind, placeholder|
      get new_money_source_path(kind: kind)

      assert_select "input#money_source_name[placeholder=?]", placeholder
    end
  end

  test "GET /money_sources/new without a kind uses the generic name placeholder" do
    get new_money_source_path

    assert_select "input#money_source_name[placeholder=?]", "p. ej. Ahorros Bancolombia"
    assert_select "select#money_source_kind option[data-name-placeholder=?]", "p. ej. Tarjeta Gold"
  end

  test "GET /money_sources/new for an account preselects the kind and hides the selector" do
    get new_money_source_path(kind: "account")

    assert_response :success
    assert_select "h4", text: "Nueva cuenta"
    assert_select "input[type=submit][value='Guardar cuenta']"
    assert_select "input[type=hidden][name='money_source[kind]'][value='account']"
    assert_select "select#money_source_kind", count: 0
    assert_select "[data-kind-panel='account wallet']" do
      assert_select "[data-institution-combobox]", count: 1
      assert_select "input#money_source_identifier", count: 1
    end
  end

  test "GET /money_sources/new for cash only asks for the starting balance" do
    get new_money_source_path(kind: "cash")

    assert_response :success
    assert_select "h4", text: "Nuevo efectivo"
    assert_select "[data-kind-panel='cash']" do
      assert_select "input[name='money_source[starting_balance]']", count: 1
      assert_select "[data-institution-combobox]", count: 0
      assert_select "input#money_source_identifier", count: 0
    end
  end

  test "GET /money_sources/new for a pocket preselects the kind and hides the selector" do
    get new_money_source_path(kind: "pocket")

    assert_response :success
    assert_select "h4", text: "Nuevo bolsillo"
    assert_select "input[type=submit][value='Guardar bolsillo']"
    assert_select "input[type=hidden][name='money_source[kind]'][value='pocket']"
    assert_select "select#money_source_kind", count: 0
  end

  test "GET /money_sources/new without a kind keeps the selector visible" do
    get new_money_source_path

    assert_response :success
    assert_select "select#money_source_kind", count: 1
    assert_select "input[type=hidden][name='money_source[kind]']", count: 0
  end

  test "GET /money_sources/new ignores an unknown kind" do
    get new_money_source_path(kind: "bogus")

    assert_response :success
    assert_select "h4", text: "Nueva Fuente de Dinero"
    assert_select "select#money_source_kind", count: 1
    assert_select "input[type=hidden][name='money_source[kind]']", count: 0
  end

  test "GET /money_sources/new shows save and cancel buttons instead of a full-width submit" do
    get new_money_source_path(kind: "pocket")

    assert_response :success
    assert_select "form[action='#{money_sources_path}'] .card" do
      assert_select ".card-header .icon-chip i.ti-pig-money"
      assert_select ".card-header h4", text: "Nuevo bolsillo"
      assert_select ".card-header .card-subtitle", text: "Completa los datos de tu bolsillo."
      assert_select ".card-footer input[type=submit].btn.btn-primary[value='Guardar bolsillo']"
      assert_select ".card-footer a.btn.btn-outline-secondary[href=?]", money_sources_pockets_path, text: "Cancelar"
    end
    assert_select ".d-grid", count: 0
  end

  test "GET /money_sources/new uses a subtitle per kind" do
    {
      "account" => "Completa los datos de tu cuenta.",
      "debit_card" => "Completa los datos de tu tarjeta débito.",
      "credit_card" => "Completa los datos de tu tarjeta de crédito.",
      "cash" => "Completa los datos de tu efectivo.",
      "wallet" => "Completa los datos de tu monedero.",
      "pocket" => "Completa los datos de tu bolsillo.",
      "loan" => "Completa los datos de tu deuda."
    }.each do |kind, subtitle|
      get new_money_source_path(kind: kind)

      assert_response :success
      assert_select ".card-header .card-subtitle", text: subtitle
    end

    get new_money_source_path
    assert_response :success
    assert_select ".card-header .card-subtitle", text: "Completa los datos de tu fuente de dinero."
  end

  test "GET /money_sources/:id/edit cancel returns to the source section" do
    card = create_source(name: "Visa", kind: "credit_card")

    get edit_money_source_path(card)

    assert_response :success
    assert_select "form[action='#{money_source_path(card)}'] .card" do
      assert_select ".card-header .icon-chip i.ti-credit-card"
      assert_select ".card-header .card-subtitle", text: "Completa los datos de tu tarjeta de crédito."
      assert_select ".card-footer input[type=submit].btn.btn-primary[value='Guardar tarjeta de crédito']"
      assert_select ".card-footer a.btn.btn-outline-secondary[href=?]", money_sources_credit_cards_path, text: "Cancelar"
    end
    assert_select ".d-grid", count: 0
  end

  test "GET /money_sources/:id/edit for a credit card uses the card wording in the title and submit button" do
    card = create_source(name: "Visa", kind: "credit_card")

    get edit_money_source_path(card)

    assert_response :success
    assert_select "h4", text: "Editar tarjeta de crédito"
    assert_select "input[type=submit][value='Guardar tarjeta de crédito']"
  end

  test "GET /money_sources/:id/edit for an account uses the account wording in the title and submit button" do
    account = create_source(name: "Ahorros", kind: "account")

    get edit_money_source_path(account)

    assert_response :success
    assert_select "h4", text: "Editar cuenta"
    assert_select "input[type=submit][value='Guardar cuenta']"
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

  test "POST /money_sources redirects a new pocket to the pockets section" do
    assert_difference "MoneySource.count", 1 do
      post money_sources_path, params: {
        money_source: { name: "Bolsillo Viaje", kind: "pocket" }
      }
    end

    assert_redirected_to money_sources_pockets_path
  end

  test "GET show for a pocket links back to the pockets section" do
    pocket = create_source(name: "Bolsillo Viaje", kind: "pocket")

    get money_source_path(pocket)

    assert_response :success
    assert_select "a[href=?]", money_sources_pockets_path
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

  test "loan show hides the recognition card" do
    loan = create_source(name: "Libre Inversión", kind: "loan", sub_kind: "personal")
    get money_source_path(loan)
    assert_response :success
    assert_select "h5.card-title", text: I18n.t("money_sources.show.recognition"), count: 0
  end

  test "payment source show keeps the recognition card" do
    source = create_source
    get money_source_path(source)
    assert_response :success
    assert_select "h5.card-title", text: I18n.t("money_sources.show.recognition"), count: 1
  end

  test "GET /money_sources/:id/edit renders edit form" do
    source = create_source
    get edit_money_source_path(source)
    assert_response :success
    assert_select "form"
  end

  test "loan edit form hides the recognition section" do
    loan = create_source(name: "Libre Inversión", kind: "loan", sub_kind: "personal")
    get edit_money_source_path(loan)
    assert_response :success
    assert_select "h6", text: I18n.t("money_sources.form.recognition_title"), count: 0
  end

  test "payment source edit form keeps the recognition section" do
    source = create_source
    get edit_money_source_path(source)
    assert_response :success
    assert_select "h6", text: I18n.t("money_sources.form.recognition_title"), count: 1
  end

  test "PATCH /money_sources/:id updates the money source" do
    source = create_source
    patch money_source_path(source), params: {
      money_source: { name: "Updated Name" }
    }
    assert_redirected_to money_sources_cash_path
    assert_equal "Updated Name", source.reload.name
  end

  test "loan form keeps the subtype select and PATCH persists sub_kind" do
    loan = create_source(name: "Libre Inversión", kind: "loan", sub_kind: "personal")
    get edit_money_source_path(loan)
    assert_response :success
    assert_select "select[name='money_source[sub_kind]']"

    patch money_source_path(loan), params: { money_source: { sub_kind: "vehicle" } }
    assert_redirected_to money_sources_loans_path
    assert_equal "vehicle", loan.reload.sub_kind
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

  test "GET /money_sources/loans renders a loan card without error" do
    source = create_source(name: "Car Loan", kind: "loan", bank: "Banco")
    source.build_credit_account(principal_amount: 114000000, outstanding_balance: 95000000,
                                installment_count: 72, installment_amount: 2686800,
                                payment_frequency: "monthly", interest_rate: 21.27,
                                interest_rate_type: "effective_annual")
    source.save!
    get money_sources_loans_path
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

  # ----- Quick transfer actions on the money source cards -----

  test "GET /money_sources/cash offers each card only the quick actions its kind allows" do
    create_source(name: "Checking", kind: "account", starting_balance: 100)
    create_source(name: "Efectivo", kind: "cash", starting_balance: 100)
    create_source(name: "Visa", kind: "credit_card", starting_balance: -3000000)
    create_source(name: "Bolsillo", kind: "pocket")
    create_source(name: "Prestamo", kind: "loan", sub_kind: "personal")

    get money_sources_cash_path
    assert_response :success

    # Only the bank account can retire cash into the existing cash source.
    assert_select "[data-testid='quick-action-withdraw']", count: 1
    # Transfer offers on bank account + cash (deposit); never on a debt.
    assert_select "[data-testid='quick-action-transfer']", count: 2
    # Pocket is reachable from bank account + cash (money inside the pocket changes form but is not spent); never from a debt.
    assert_select "[data-testid='quick-action-pocket']", count: 2
    # Debt cards are not part of the cash section.
    assert_select "[data-testid='quick-action-advance']", count: 0

    get money_sources_credit_cards_path
    # The credit card moves money out through its own advance action.
    assert_select "[data-testid='quick-action-advance']", count: 1
  end

  test "the withdraw quick action disappears when no active cash source exists" do
    create_source(name: "Checking", kind: "account", starting_balance: 100)

    get money_sources_cash_path
    assert_select "[data-testid='quick-action-withdraw']", count: 0
    assert_select "[data-testid='quick-action-transfer']", count: 1
  end

  test "inactive sources do not offer quick transfer actions" do
    create_source(name: "Checking", kind: "account", starting_balance: 100, active: false)
    create_source(name: "Efectivo", kind: "cash", starting_balance: 100)

    get money_sources_cash_path
    assert_select "[data-testid='quick-action-withdraw']", count: 0
  end

  test "GET /money_sources/cash shows the deposit action on the cash card" do
    create_source(name: "Checking", kind: "account", starting_balance: 100)
    create_source(name: "Efectivo", kind: "cash", starting_balance: 100)

    get money_sources_cash_path
    assert_response :success
    assert_select "[data-testid='quick-action-withdraw']", count: 1
    # Deposit (cash) + transfer (account) + goals available that can send to pocket.
    assert_select "[data-testid='quick-action-transfer']", count: 2
    assert_select "[data-testid='quick-action-pocket']", count: 2
  end

  test "GET /money_sources/recognition renders the payment source kinds (pockets excluded)" do
    create_source(name: "Cuenta", kind: "account")
    create_source(name: "Efectivo", kind: "cash")
    create_source(name: "Bolsillo", kind: "pocket")

    get money_sources_recognition_path
    assert_response :success
    assert_select "[data-testid='recognition-row']", count: 2
    assert_select "[data-testid='recognition-row']", text: /Cuenta/, count: 1
    assert_select "[data-testid='recognition-row']", text: /Efectivo/, count: 1
    assert_select "[data-testid='recognition-row']", text: /Bolsillo/, count: 0
  end

  test "the money source show page renders the quick transfer actions and modal" do
    account = create_source(name: "Checking", kind: "account", starting_balance: 100)
    create_source(name: "Efectivo", kind: "cash", starting_balance: 100)

    get money_source_path(account)
    assert_response :success
    assert_select "[data-testid='quick-transfer-modal']", count: 1
    assert_select "button[data-testid='quick-action-withdraw']", count: 1
    assert_select "button[data-testid='quick-action-transfer']", count: 1
    assert_select "button[data-testid='quick-action-pocket']", count: 1
  end

  test "the credit card show page only offers the advance quick action" do
    card = create_source(name: "Visa", kind: "credit_card", starting_balance: -3000000)

    get money_source_path(card)
    assert_response :success
    assert_select "button[data-testid='quick-action-withdraw']", count: 0
    assert_select "button[data-testid='quick-action-advance']", count: 1
    assert_select "button[data-testid='quick-action-transfer']", count: 0
    assert_select "button[data-testid='quick-action-pocket']", count: 0
  end

  test "the loan show page offers no quick transfer actions" do
    loan = create_source(name: "Prestamo", kind: "loan", sub_kind: "personal")

    get money_source_path(loan)
    assert_response :success
    assert_select "[data-testid='quick-action-transfer']", count: 0
    assert_select "[data-testid='quick-action-withdraw']", count: 0
    assert_select "[data-testid='quick-action-pocket']", count: 0
  end

  # ----- Tabs on the money source show page -----

  test "a debt show page renders tabs and defaults to the summary tab" do
    loan = create_source(name: "Car Loan", kind: "loan", sub_kind: "personal")

    get money_source_path(loan)
    assert_response :success
    assert_select "[data-source-tabs]"
    assert_select ".nav-tabs [data-tab-slug='resumen']", count: 1
    assert_select ".nav-tabs [data-tab-slug='pagos']", count: 1
    assert_select ".nav-tabs [data-tab-slug='abonos']", count: 1
    assert_select ".nav-tabs [data-tab-slug='resumen'].active", count: 1
    assert_select ".tab-pane#source-tab-resumen.active"
  end

  test "a loan show page has no recognition tab" do
    loan = create_source(name: "Car Loan", kind: "loan", sub_kind: "personal")

    get money_source_path(loan)
    assert_response :success
    assert_select ".nav-tabs [data-tab-slug='reconocimiento']", count: 0
  end

  test "a revolving loan show page renders summary, payments and extras tabs" do
    loan = create_source(name: "Credito Rotativo", kind: "loan", sub_kind: "revolving")

    get money_source_path(loan)
    assert_response :success
    assert_select ".nav-tabs [data-tab-slug='resumen']", count: 1
    assert_select ".nav-tabs [data-tab-slug='pagos']", count: 1
    assert_select ".nav-tabs [data-tab-slug='abonos']", count: 1
    assert_select ".nav-tabs [data-tab-slug='reconocimiento']", count: 0
  end

  test "a credit card show page renders the recognition tab" do
    card = create_source(name: "Visa", kind: "credit_card")

    get money_source_path(card)
    assert_response :success
    assert_select ".nav-tabs [data-tab-slug='reconocimiento']", count: 1
    assert_select ".nav-tabs [data-tab-slug='abonos']", count: 1
  end

  test "a non-debt payment source show page renders summary and movements tabs" do
    account = create_source(name: "Checking", kind: "account", starting_balance: 100)

    get money_source_path(account)
    assert_response :success
    assert_select ".nav-tabs [data-tab-slug='resumen']", count: 1
    assert_select ".nav-tabs [data-tab-slug='movimientos']", count: 1
    assert_select ".nav-tabs [data-tab-slug='pagos']", count: 0
    assert_select ".nav-tabs [data-tab-slug='abonos']", count: 0
  end

  test "a pocket show page renders summary and movements tabs" do
    pocket = create_source(name: "Bolsillo", kind: "pocket")

    get money_source_path(pocket)
    assert_response :success
    assert_select ".nav-tabs [data-tab-slug='resumen']", count: 1
    assert_select ".nav-tabs [data-tab-slug='movimientos']", count: 1
  end

  test "POST /money_sources rejects a parent owned by another user" do
    other_user = User.create!(name: "Other", email: "money_sources_foreign_parent@example.com",
                              password: "password123")
    foreign_account = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account",
                                                       starting_balance: 1_000_000)

    assert_no_difference "MoneySource.count" do
      post money_sources_path, params: {
        money_source: { name: "Débito Ajeno", kind: "debit_card", parent_id: foreign_account.id,
                        starting_balance: 0 }
      }
    end

    assert_response :unprocessable_entity
  end

  test "PATCH /money_sources/:id rejects changing the parent to another user's account" do
    own_account = create_source(name: "Cuenta Propia", kind: "account")
    card = create_source(name: "Débito Propio", kind: "debit_card", parent: own_account)
    other_user = User.create!(name: "Other", email: "money_sources_foreign_parent_update@example.com",
                              password: "password123")
    foreign_account = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account",
                                                       starting_balance: 1_000_000)

    patch money_source_path(card), params: { money_source: { parent_id: foreign_account.id } }

    assert_response :unprocessable_entity
    assert_equal own_account, card.reload.parent
  end

  test "POST /money_sources accepts a parent owned by the same user" do
    account = create_source(name: "Cuenta Propia", kind: "account")

    assert_difference "MoneySource.count", 1 do
      post money_sources_path, params: {
        money_source: { name: "Débito Propio", kind: "debit_card", parent_id: account.id,
                        starting_balance: 0 }
      }
    end

    assert_redirected_to money_sources_cash_path
    assert_equal account, MoneySource.find_by(name: "Débito Propio").parent
  end

  test "rejected foreign parent attempts leave the other user's cached balance untouched" do
    other_user = User.create!(name: "Other", email: "money_sources_foreign_balance@example.com",
                              password: "password123")
    foreign_account = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account",
                                                       starting_balance: 2_500_000)
    balance_before = foreign_account.reload.cached_balance

    assert_no_difference "MoneySource.count" do
      post money_sources_path, params: {
        money_source: { name: "Débito Ajeno", kind: "debit_card", parent_id: foreign_account.id,
                        starting_balance: 0 }
      }
    end

    assert_response :unprocessable_entity
    assert_equal balance_before, foreign_account.reload.cached_balance
  end
end
