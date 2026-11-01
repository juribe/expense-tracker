# frozen_string_literal: true

require "test_helper"

class TransactionBalanceGuardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "balance_guard_test@example.com", password: "password123")
    @category = Category.create!(name: "Food #{Time.now.to_i}")
  end

  def create_account(name: "Savings", starting_balance: 1000)
    @user.money_sources.create!(name: "#{name} #{Time.now.to_i}", kind: "account", starting_balance: starting_balance)
  end

  def create_source(kind:, name: nil, starting_balance: 0, **overrides)
    name ||= kind.to_s.capitalize
    @user.money_sources.create!(
      { name: "#{name} #{Time.now.to_i}", kind: kind, starting_balance: starting_balance }.merge(overrides)
    )
  end

  test "gasto manual con saldo suficiente se guarda" do
    source = create_account(starting_balance: 1000)
    tx = source.transactions.new(user: @user, category: @category, amount: -300, date: Date.current, kind: "expense", source: "manual")
    assert tx.valid?, tx.errors.full_messages.to_sentence
    assert tx.save
  end

  test "gasto manual que excede el saldo se rechaza con mensaje de disponible y faltante" do
    source = create_account(starting_balance: 1000)
    tx = source.transactions.new(user: @user, category: @category, amount: -1500, date: Date.current, kind: "expense", source: "manual")
    assert_not tx.valid?
    errors = tx.errors.full_messages.join(" ")
    assert_includes errors, "saldo suficiente"
    assert_includes errors, "disponible"
    assert_includes errors, "faltan"
  end

  test "gasto manual igual al saldo se permite" do
    source = create_account(starting_balance: 500)
    tx = source.transactions.new(user: @user, category: @category, amount: -500, date: Date.current, kind: "expense", source: "manual")
    assert tx.valid?, tx.errors.full_messages.to_sentence
  end

  test "el ajuste de cuadre (balance_offset) cuenta como disponible" do
    source = create_account(starting_balance: 100)
    source.update!(balance_offset: 400)
    tx = source.transactions.new(user: @user, category: @category, amount: -450, date: Date.current, kind: "expense", source: "manual")
    assert tx.valid?, tx.errors.full_messages.to_sentence
  end

  test "un ingreso manual nunca se bloquea por saldo" do
    source = create_account(starting_balance: 0)
    tx = source.transactions.new(user: @user, category: @category, amount: 100, date: Date.current, kind: "income", source: "manual")
    assert tx.valid?, tx.errors.full_messages.to_sentence
  end

  test "gasto automatico de Gmail con saldo insuficiente se registra" do
    source = create_account(starting_balance: 10)
    tx = source.transactions.new(user: @user, category: @category, amount: -500, date: Date.current, kind: "expense", source: "gmail")
    assert tx.valid?, tx.errors.full_messages.to_sentence
  end

  test "extractos, plantillas recurrentes y wizard tampoco se bloquean" do
    source = create_account(starting_balance: 10)
    tx1 = source.transactions.new(user: @user, category: @category, amount: -100, date: Date.current, kind: "expense", source: "statement_file")
    assert tx1.valid?
    tx2 = source.transactions.new(user: @user, category: @category, amount: -100, date: Date.current, kind: "expense", source: "recurring_template")
    assert tx2.valid?
    tx3 = source.transactions.new(user: @user, category: @category, amount: -100, date: Date.current, kind: "expense", source: "wizard")
    assert tx3.valid?
  end

  test "entradas de WhatsApp e IA no se bloquean" do
    source = create_account(starting_balance: 10)
    tx1 = source.transactions.new(user: @user, category: @category, amount: -100, date: Date.current, kind: "expense", source: "whatsapp")
    assert tx1.valid?
    tx2 = source.transactions.new(user: @user, category: @category, amount: -100, date: Date.current, kind: "expense", source: "ai")
    assert tx2.valid?
  end

  test "tarjetas de credito nunca pasan por la validacion de saldo" do
    cc = create_source(kind: "credit_card", starting_balance: -1000)
    tx = cc.transactions.new(user: @user, category: @category, amount: -2000, date: Date.current, kind: "expense", source: "manual")
    assert tx.valid?, tx.errors.full_messages.to_sentence
  end

  test "gasto con tarjeta debito mira el saldo de la cuenta madre" do
    account = create_account(starting_balance: 100)
    card = create_source(kind: "debit_card", starting_balance: 0, parent: account)
    tx = card.transactions.new(user: @user, category: @category, amount: -200, date: Date.current, kind: "expense", source: "manual")
    assert_not tx.valid?
  end

  test "gasto con debito permitido cuando la cuenta madre cubre el monto" do
    account = create_account(starting_balance: 500)
    card = create_source(kind: "debit_card", starting_balance: 0, parent: account)
    tx = card.transactions.new(user: @user, category: @category, amount: -200, date: Date.current, kind: "expense", source: "manual")
    assert tx.valid?, tx.errors.full_messages.to_sentence
  end
end
