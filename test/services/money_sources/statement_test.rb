# frozen_string_literal: true

require "test_helper"

class MoneySources::StatementTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Stmt User", email: "stmt_test@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1000)
  end

  test "opening balance uses starting balance" do
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal BigDecimal("1000"), result.opening_balance
  end

  test "includes income and expense transactions" do
    @user.expenses.create!(money_source: @source, amount: 200, date: Date.current, description: "Gasto", source: "manual")
    @user.incomes.create!(money_source: @source, amount: 500, date: Date.current, description: "Ingreso", source: "manual")

    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal 2, result.total_count
    assert_equal BigDecimal("500"), result.entries_total
    assert_equal BigDecimal("200"), result.exits_total
  end

  test "transfer appears as out in origin and in in destination" do
    dest = @user.money_sources.create!(name: "Billetera", kind: "wallet", starting_balance: 0)
    transfer = Transfer.create!(user: @user, from_source: @source, to_source: dest, amount: 300, date: Date.current)

    origin_result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    dest_result = MoneySources::Statement.new(user: @user, source: dest, period: "current").call

    assert_equal 1, origin_result.total_count
    assert_equal "out", origin_result.movements.first.direction
    assert_equal 1, dest_result.total_count
    assert_equal "in", dest_result.movements.first.direction
  end

  test "search filters movements" do
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Supermercado", source: "manual")
    @user.expenses.create!(money_source: @source, amount: 50, date: Date.current, description: "Transporte", source: "manual")

    result = MoneySources::Statement.new(user: @user, source: @source, period: "current", query: "super").call
    assert_equal 1, result.total_count
  end

  test "kind filter out" do
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Gasto", source: "manual")
    @user.incomes.create!(money_source: @source, amount: 50, date: Date.current, description: "Ingreso", source: "manual")

    result = MoneySources::Statement.new(user: @user, source: @source, period: "current", kind: "out").call
    assert_equal 1, result.total_count
    assert_equal "out", result.movements.first.direction
  end

  test "pagination" do
    5.times do |i|
      @user.expenses.create!(money_source: @source, amount: 10, date: Date.current, description: "Gasto #{i}", source: "manual")
    end
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current", per_page: 2, page: 2).call
    assert_equal 2, result.movements.size
    assert_equal 5, result.total_count
  end

  test "manual adjustment appears as movement" do
    BalanceAdjustment.create!(user: @user, money_source: @source, effective_date: Date.current, delta: 300, note: "Ajuste manual")
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal 1, result.total_count
    assert_equal "Ajuste de saldo", result.movements.first.movement_type
    assert_equal "in", result.movements.first.direction
  end

  test "adjustment before period affects opening balance" do
    BalanceAdjustment.create!(user: @user, money_source: @source, effective_date: Date.current - 1.year, delta: 300, note: "Ajuste")
    result = MoneySources::Statement.new(user: @user, source: @source, period: "current").call
    assert_equal BigDecimal("1300"), result.opening_balance
  end

  test "isolates users" do
    other = User.create!(name: "Other", email: "other_stmt@example.com", password: "password123")
    other_source = other.money_sources.create!(name: "Otra", kind: "account", starting_balance: 0)
    @user.expenses.create!(money_source: @source, amount: 100, date: Date.current, description: "Gasto", source: "manual")

    result = MoneySources::Statement.new(user: other, source: other_source, period: "current").call
    assert_equal 0, result.total_count
  end

  test "credit card statement shows purchases and payments against the debt" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)
    purchase = Expense.create!(user: @user, amount: 500, date: Date.current,
                               description: "Compra", source: "manual", money_source: card)
    payment_expense = Expense.create!(user: @user, amount: 200, date: Date.current,
                                      description: "Pago tarjeta", source: "manual", money_source: funding)
    Payment.create!(user: @user, expense: payment_expense, money_source: card, date: Date.current,
                    amount: 200, principal_amount: 200, interest_amount: 0,
                    insurance_amount: 0, other_amount: 0)

    result = MoneySources::Statement.new(user: @user, source: card, period: "current").call

    assert_equal BigDecimal("-300"), result.closing_balance
    assert_equal 2, result.total_count
    assert_equal [ "Pago", "Compra" ], result.movements.map(&:movement_type)
    assert_equal 200.to_d, result.entries_total
    assert_equal 500.to_d, result.exits_total
    assert_equal purchase.id, result.movements.last.reference
  end

  test "credit card payment reduces debt by principal only and shows the other components" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)
    Expense.create!(user: @user, amount: 500, date: Date.current,
                    description: "Compra", source: "manual", money_source: card)
    payment_expense = Expense.create!(user: @user, amount: 300, date: Date.current,
                                      description: "Pago tarjeta", source: "manual", money_source: funding)
    Payment.create!(user: @user, expense: payment_expense, money_source: card, date: Date.current,
                    amount: 300, principal_amount: 200, interest_amount: 100,
                    insurance_amount: 0, other_amount: 0)

    result = MoneySources::Statement.new(user: @user, source: card, period: "current").call
    payment_movement = result.movements.find { |movement| movement.movement_type == "Pago" }

    assert_equal 200.to_d, payment_movement.amount
    assert_match(/Intereses/, payment_movement.secondary)
    assert_equal BigDecimal("-300"), result.closing_balance
  end

  test "extra payment is labeled without duplicating the payment movement" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)
    Expense.create!(user: @user, amount: 500, date: Date.current,
                    description: "Compra", source: "manual", money_source: card)
    payment_expense = Expense.create!(user: @user, amount: 200, date: Date.current,
                                      description: "Abono", source: "manual", money_source: funding)
    payment = Payment.create!(user: @user, expense: payment_expense, money_source: card,
                              date: Date.current, amount: 200, principal_amount: 200,
                              interest_amount: 0, insurance_amount: 0, other_amount: 0)
    CreditExtraPayment.create!(money_source: card, funding_money_source: funding,
                               date: Date.current, amount: 200, application_type: "reduce_balance",
                               principal_reduction: 200, payment_id: payment.id)

    result = MoneySources::Statement.new(user: @user, source: card, period: "current").call
    extra_movements = result.movements.select { |movement| movement.movement_type == "Abono" }

    assert_equal 1, extra_movements.size
    assert_equal payment.id, extra_movements.first.reference
    assert_equal BigDecimal("-300"), result.closing_balance
  end

  test "credit card opening balance includes payments from previous periods" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)
    Expense.create!(user: @user, amount: 500, date: Date.current.prev_month,
                    description: "Compra", source: "manual", money_source: card)
    payment_expense = Expense.create!(user: @user, amount: 200, date: Date.current.prev_month,
                                      description: "Pago tarjeta", source: "manual", money_source: funding)
    Payment.create!(user: @user, expense: payment_expense, money_source: card,
                    date: Date.current.prev_month, amount: 200, principal_amount: 200,
                    interest_amount: 0, insurance_amount: 0, other_amount: 0)

    result = MoneySources::Statement.new(user: @user, source: card, period: "current").call

    assert_equal BigDecimal("-300"), result.opening_balance
  end

  test "credit card statement excludes a payment made from the same card" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    Expense.create!(user: @user, amount: 500, date: Date.current,
                    description: "Compra", source: "manual", money_source: card)
    internal_expense = Expense.create!(user: @user, amount: 200, date: Date.current,
                                       description: "Pago interno", source: "manual", money_source: card)
    Payment.create!(user: @user, expense: internal_expense, money_source: card, date: Date.current,
                    amount: 200, principal_amount: 200, interest_amount: 0,
                    insurance_amount: 0, other_amount: 0)

    result = MoneySources::Statement.new(user: @user, source: card, period: "current").call

    assert_equal BigDecimal("-700"), result.closing_balance
    assert_equal 0.to_d, result.entries_total
    assert_equal 700.to_d, result.exits_total
    assert_equal 2, result.total_count
  end

  test "loan statement uses outstanding balance and only principal reduces it" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(principal_amount: 1_000, outstanding_balance: 1_000, installment_count: 12)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)
    payment_expense = Expense.create!(user: @user, amount: 300, date: Date.current,
                                      description: "Cuota", source: "manual", money_source: funding)
    Payment.create!(user: @user, expense: payment_expense, money_source: loan, date: Date.current,
                    amount: 300, principal_amount: 200, interest_amount: 100,
                    insurance_amount: 0, other_amount: 0)
    loan.credit_account.reload

    result = MoneySources::Statement.new(user: @user, source: loan, period: "current").call

    assert_equal BigDecimal("-1000"), result.opening_balance
    assert_equal BigDecimal("200"), result.entries_total
    assert_equal BigDecimal("-800"), result.closing_balance
    assert_equal "Pago", result.movements.first.movement_type
  end

  test "revolving loan statement shows usage and transfer payments" do
    line = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving")
    line.create_credit_account!(principal_amount: 0, outstanding_balance: 0)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)

    Expense.create!(user: @user, amount: 400, date: Date.current,
                    description: "Uso", source: "manual", money_source: line)
    Transfer.create!(user: @user, from_source: funding, to_source: line,
                     amount: 150, date: Date.current)
    line.credit_account.reload

    result = MoneySources::Statement.new(user: @user, source: line, period: "current").call

    assert_equal BigDecimal("400"), result.exits_total
    assert_equal BigDecimal("150"), result.entries_total
    assert_equal BigDecimal("-250"), result.closing_balance
    assert_equal [ "Pago", "Uso" ], result.movements.map(&:movement_type)
  end

  test "revolving loan disbursement by transfer is labeled as a transfer" do
    line = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving")
    line.create_credit_account!(principal_amount: 0, outstanding_balance: 0)
    account = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 0)

    Transfer.create!(user: @user, from_source: line, to_source: account,
                     amount: 300, date: Date.current)
    line.credit_account.reload

    result = MoneySources::Statement.new(user: @user, source: line, period: "current").call

    assert_equal "Transferencia", result.movements.first.movement_type
    assert_equal "out", result.movements.first.direction
    assert_equal BigDecimal("-300"), result.closing_balance
  end

  test "loan historical period excludes later payments from its closing balance" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(principal_amount: 1_000, outstanding_balance: 1_000)
    funding = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000)
    payment_expense = Expense.create!(user: @user, amount: 200, date: Date.current,
                                      description: "Cuota", source: "manual", money_source: funding)
    Payment.create!(user: @user, expense: payment_expense, money_source: loan, date: Date.current,
                    amount: 200, principal_amount: 200, interest_amount: 0,
                    insurance_amount: 0, other_amount: 0)
    loan.credit_account.reload

    result = MoneySources::Statement.new(user: @user, source: loan, period: "lastmonth").call

    assert_equal BigDecimal("-1000"), result.opening_balance
    assert_equal BigDecimal("-1000"), result.closing_balance
    assert_equal 0, result.total_count
  end

  test "loan statement anchors on the current outstanding balance, not the original principal" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(principal_amount: 40_000_000, outstanding_balance: 32_000_000)

    result = MoneySources::Statement.new(user: @user, source: loan, period: "current").call

    assert_equal BigDecimal("-32000000"), result.opening_balance
    assert_equal BigDecimal("-32000000"), result.closing_balance
    assert_equal 0, result.total_count
  end

  test "loan adjustment increases and reduces debt according to its sign" do
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage")
    loan.create_credit_account!(principal_amount: 1_000, outstanding_balance: 1_000)

    MoneySources::BalanceAdjust.call(source: loan, actual_balance: 900, note: "Saldo banco")
    result = MoneySources::Statement.new(user: @user, source: loan, period: "current").call

    assert_equal BigDecimal("-900"), result.closing_balance
    assert_equal "Ajuste de saldo", result.movements.first.movement_type
    assert_equal "in", result.movements.first.direction
  end
end
