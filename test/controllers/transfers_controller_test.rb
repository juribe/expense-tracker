# frozen_string_literal: true

require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(
      name: "Test User",
      email: "transfers_ctrl_test@example.com",
      password: "password123"
    )
    sign_in @user
    @savings = @user.money_sources.create!(name: "Savings", kind: "account", starting_balance: 1000)
    @checking = @user.money_sources.create!(name: "Checking", kind: "account", starting_balance: 0)
  end

  def create_transfer(amount: 100)
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: amount, date: Date.today)
  end

  test "GET /transfers renders the index" do
    create_transfer
    get transfers_path
    assert_response :success
    assert_select "h1", text: I18n.t("transfers.index.title")
  end

  test "the sidebar links to the transfers section" do
    get transfers_path
    assert_response :success
    assert_select "aside.left-sidebar a[href='#{transfers_path}']" do
      assert_select "span", text: I18n.t("nav.transfers")
    end
  end

  test "GET /transfers shows empty state when no transfers" do
    get transfers_path
    assert_response :success
  end

  test "GET /transfers shows the financial cycle badge in the title with a schedule" do
    @user.update!(financial_cycle_start_day: 20)
    cycle = PayCycle.current(@user)

    get transfers_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.label}/
    assert_select "[data-testid=cycle-badge]", text: /#{cycle.range_label}/
  end

  test "GET /transfers hides the cycle badge without a configured schedule" do
    get transfers_path

    assert_response :success
    assert_select "[data-testid=cycle-badge]", count: 0
  end

  test "POST /transfers creates a transfer" do
    assert_difference "Transfer.count", 1 do
      post transfers_path, params: {
        transfer: {
          from_source_id: @savings.id,
          to_source_id: @checking.id,
          amount: 200,
          date: Date.today.to_s,
          note: "Monthly transfer"
        }
      }
    end
    assert_redirected_to transfers_path
    follow_redirect!
    assert_equal I18n.t("transfers.flashes.created"), flash[:notice]
  end

  test "POST /transfers without quick context redirects with an alert" do
    post transfers_path, params: {
      transfer: {
        from_source_id: @savings.id,
        to_source_id: @savings.id,
        amount: 100,
        date: Date.today.to_s
      }
    }
    assert_redirected_to transfers_path
    assert flash[:alert].present?
    assert_no_difference "Transfer.count" do
      post transfers_path, params: {
        transfer: {
          from_source_id: @savings.id,
          to_source_id: @savings.id,
          amount: 100,
          date: Date.today.to_s
        }
      }
    end
  end

  test "DELETE /transfers/:id destroys the transfer" do
    transfer = create_transfer
    assert_difference "Transfer.count", -1 do
      delete transfer_path(transfer)
    end
    assert_redirected_to transfers_path
  end

  test "POST /transfers above the origin balance redirects with the balance message" do
    assert_no_difference "Transfer.count" do
      post transfers_path, params: { transfer: {
        from_source_id: @savings.id,
        to_source_id: @checking.id,
        amount: 5_000,
        date: Date.today.to_s
      } }
    end

    assert_redirected_to transfers_path
    assert_match(/saldo suficiente/i, flash[:alert].to_s)
    assert_equal BigDecimal("1000"), @savings.reload.balance
  end

  test "POST /transfers quick withdraw above the origin balance re-renders with the balance message" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 0)

    assert_no_difference "Transfer.count" do
      post transfers_path, params: {
        quick: "1", mode: "withdraw",
        transfer: {
          from_source_id: @savings.id,
          to_source_id: cash.id,
          amount: 5_000,
          date: Date.today.to_s
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/saldo suficiente/i, response.body)
    assert_equal BigDecimal("1000"), @savings.reload.balance
  end

  test "transfer affects balances correctly" do
    create_transfer(amount: 200)
    assert_equal BigDecimal("800"), @savings.reload.balance
    assert_equal BigDecimal("200"), @checking.reload.balance
  end

  test "user cannot delete other user's transfer" do
    other_user = User.create!(name: "Other", email: "other_transfer_ctrl@example.com", password: "password123")
    other_a = other_user.money_sources.create!(name: "A", kind: "account", starting_balance: 100)
    other_b = other_user.money_sources.create!(name: "B", kind: "account")
    other_transfer = Transfer.create!(user: other_user, from_source: other_a, to_source: other_b, amount: 50, date: Date.today)
    delete transfer_path(other_transfer)
    assert_response :not_found
    assert Transfer.exists?(other_transfer.id)
  end

  test "GET /transfers defaults to the current calendar month without a configured cycle" do
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: 100,
                     date: Date.current, note: "en mes")
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: 70,
                     date: Date.current.beginning_of_month.prev_month, note: "mes pasado")

    get transfers_path

    assert_response :success
    assert_includes response.body, "en mes"
    refute_includes response.body, "mes pasado"
  end

  test "GET /transfers defaults to the current cycle with a configured cycle" do
    @user.update!(financial_cycle_start_day: 20)
    current_cycle = PayCycle.current(@user)
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: 100,
                     date: current_cycle.starts + 2, note: "en ciclo")
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: 90,
                     date: current_cycle.ends + 3, note: "fuera de ciclo")

    get transfers_path

    assert_response :success
    assert_select "form input[name='start_date']"
    assert_includes response.body, "en ciclo"
    refute_includes response.body, "fuera de ciclo"
  end

  test "GET /transfers accepts explicit date bounds" do
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: 100,
                     date: Date.new(2026, 3, 5), note: "en rango")
    Transfer.create!(user: @user, from_source: @savings, to_source: @checking, amount: 60,
                     date: Date.new(2026, 3, 28), note: "rango fuera")

    get transfers_path, params: { start_date: "2026-03-01", end_date: "2026-03-10" }

    assert_response :success
    assert_includes response.body, "en rango"
    refute_includes response.body, "rango fuera"
  end

  # ----- Transfer to pocket with optional goal allocation -----

  test "POST /transfers into a pocket with a goal assigns the money to it" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje Europa", target_amount: 20_000_000)
    @savings.update!(starting_balance: 2_000_000)

    assert_difference([ "Transfer.count", "GoalAllocation.count" ], 1) do
      post transfers_path, params: { transfer: {
        from_source_id: @savings.id, to_source_id: pocket.id, amount: "1.000.000",
        date: Date.today.to_s, assign_goal_id: goal.id
      } }
    end

    allocation = GoalAllocation.last
    assert_equal goal, allocation.financial_goal
    assert_equal pocket, allocation.pocket
    assert_equal 1_000_000, allocation.amount
    # One movement, one reservation: no expense, no income.
    assert_equal 0, Expense.count
    assert_equal 0, Income.count
  end

  test "POST /transfers into a pocket without a goal leaves it unallocated" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    @savings.update!(starting_balance: 1_000_000)

    assert_difference("Transfer.count", 1) do
      assert_no_difference("GoalAllocation.count") do
        post transfers_path, params: { transfer: {
          from_source_id: @savings.id, to_source_id: pocket.id, amount: "500.000", date: Date.today.to_s
        } }
      end
    end
    assert_equal 500_000, pocket.reload.unallocated_amount.to_i
  end

  test "assign_goal_id pointing outside the destiny pocket is ignored" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    other_pocket = @user.money_sources.create!(name: "Otro", kind: "pocket", starting_balance: 0)
    other_goal = Goal.create!(user: @user, pocket: other_pocket, name: "Carro", target_amount: 5_000_000)
    @savings.update!(starting_balance: 500_000)

    assert_difference("Transfer.count", 1) do
      assert_no_difference("GoalAllocation.count") do
        post transfers_path, params: { transfer: {
          from_source_id: @savings.id, to_source_id: pocket.id, amount: "100.000",
          date: Date.today.to_s, assign_goal_id: other_goal.id
        } }
      end
    end
  end

  test "assign_goal_id is ignored when the destiny is not a pocket" do
    goal = Goal.create!(user: @user, pocket: @user.money_sources.create!(name: "B", kind: "pocket", starting_balance: 0), name: "Viaje", target_amount: 5_000_000)
    @savings.update!(starting_balance: 500_000)

    assert_difference("Transfer.count", 1) do
      assert_no_difference("GoalAllocation.count") do
        post transfers_path, params: { transfer: {
          from_source_id: @savings.id, to_source_id: @checking.id, amount: "100.000",
          date: Date.today.to_s, assign_goal_id: goal.id
        } }
      end
    end
  end

  test "destroying a transfer that fed a pocket with allocations is blocked" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje", target_amount: 5_000_000)
    @savings.update!(starting_balance: 2_000_000)
    transfer = Transfer.create!(user: @user, from_source: @savings, to_source: pocket, amount: 1_000_000, date: Date.today)
    assert_equal 1_000_000, pocket.reload.balance.to_i
    goal.goal_allocations.create!(pocket: pocket, amount: 1_000_000, date: Date.today)

    assert_no_difference("Transfer.count") do
      delete transfer_path(transfer)
    end
    assert_equal 1_000_000, pocket.reload.balance.to_i
  end

  # ----- Quick actions: compact transfer forms with a fixed origin -----

  test "GET /transfers/quick_new with mode withdraw fixes the cash destination and skips the selectors" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)

    get quick_new_transfers_path(from_source_id: @savings.id, mode: "withdraw")

    assert_response :success
    # Origin: hidden, no selector (known by context).
    assert_select "select[name='transfer[from_source_id]']", count: 0
    assert_select "input[name='transfer[from_source_id]'][value='#{@savings.id}']"
    # Destination: the cash source, hidden too.
    assert_select "select[name='transfer[to_source_id]']", count: 0
    assert_select "input[name='transfer[to_source_id]'][value='#{cash.id}']"
    # Date defaults to today and stays editable; no goal field in this mode.
    assert_select "input[type='date'][name='transfer[date]']"
    assert_select "input[name='transfer[date]'][value=?]", Date.current.iso8601
    assert_select "select[name='transfer[assign_goal_id]']", count: 0
    assert_select "textarea[name='transfer[note]']"
  end

  test "quick withdraw from POST creates a transfer into cash without any expense" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)

    assert_no_difference "Expense.count" do
      assert_difference "Transfer.count", 1 do
        post transfers_path, params: {
          quick: "1", mode: "withdraw", return_to: money_sources_cash_path,
          transfer: { from_source_id: @savings.id, to_source_id: cash.id, amount: 100, date: Date.current.to_s }
        }
      end
    end
    assert_redirected_to money_sources_cash_path
    follow_redirect!
    assert_equal I18n.t("transfers.flashes.created"), flash[:notice]
    assert_equal BigDecimal("900"), @savings.reload.balance
    assert_equal BigDecimal("200"), cash.reload.balance
  end

  test "GET /transfers/quick_new transfer offers payment destinations excluding the origin, cash and debts" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")
    wallet = @user.money_sources.create!(name: "Nequi", kind: "wallet")

    get quick_new_transfers_path(from_source_id: @savings.id, mode: "transfer")

    assert_response :success
    assert_select "select[name='transfer[from_source_id]']", count: 0
    options = css_select "select[name='transfer[to_source_id]'] option"
    values = options.map { |o| o["value"] }
    assert_includes values, @checking.id.to_s
    assert_includes values, wallet.id.to_s
    refute_includes values, @savings.id.to_s, "the origin must not offer itself as destination"
    refute_includes values, cash.id.to_s, "cash destinations belong to the withdraw action"
    refute_includes values, card.id.to_s, "paying a debt is not a plain quick transfer"
  end

  test "GET /transfers/quick_new from cash renders the deposit variant of transfer" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)

    get quick_new_transfers_path(from_source_id: cash.id, mode: "transfer")

    assert_response :success
    assert_select "select[name='transfer[to_source_id]'] option", text: /Checking/, count: 1
    assert_select "select[name='transfer[to_source_id]'] option", text: /Efectivo/, count: 0
  end

  test "GET /transfers/quick_new pocket offers pockets and their goals tagged with data-pocket-id" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje Europa", target_amount: 20_000_000)
    other_pocket = @user.money_sources.create!(name: "Otro", kind: "pocket", starting_balance: 0)
    other_goal = Goal.create!(user: @user, pocket: other_pocket, name: "Carro", target_amount: 5_000_000)

    get quick_new_transfers_path(from_source_id: @savings.id, mode: "pocket")

    assert_response :success
    destination_options = css_select("select[name='transfer[to_source_id]'] option")
                          .reject { |o| o["value"].blank? }
    assert_equal [pocket.id.to_s, other_pocket.id.to_s], destination_options.map { |o| o["value"] }
    assert_select "select[name='transfer[assign_goal_id]'] option[data-pocket-id=?]", pocket.id.to_s, text: /Viaje Europa/
    assert_select "select[name='transfer[assign_goal_id]'] option[data-pocket-id=?]", other_pocket.id.to_s, text: /Carro/
  end

  test "quick pocket POST into a pocket with a goal allocates the money" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje Europa", target_amount: 20_000_000)
    @savings.update!(starting_balance: 1_000_000)

    assert_difference([ "Transfer.count", "GoalAllocation.count" ], 1) do
      assert_no_difference "Expense.count" do
        post transfers_path, params: {
          quick: "1", mode: "pocket", return_to: money_sources_pockets_path,
          transfer: { from_source_id: @savings.id, to_source_id: pocket.id, amount: "500.000",
                      date: Date.current.to_s, assign_goal_id: goal.id }
        }
      end
    end
    assert_redirected_to money_sources_pockets_path
    allocation = GoalAllocation.last
    assert_equal goal, allocation.financial_goal
    assert_equal 500_000, allocation.amount
    # The whole transfer went to the goal: it is reserved, not left unallocated.
    assert_equal 500_000, pocket.reload.balance.to_i
    assert_equal 0, pocket.unallocated_amount.to_i
  end

  test "quick transfer validation failure re-renders the compact form with errors" do
    post transfers_path, params: {
      quick: "1", mode: "transfer",
      transfer: { from_source_id: @savings.id, to_source_id: @checking.id, amount: "", date: Date.current.to_s }
    }
    assert_response :unprocessable_entity
    assert_select "form[data-testid='quick-transfer-form']"
    # The origin selector never appears in the quick form.
    assert_select "select[name='transfer[from_source_id]']", count: 0
  end

  test "GET /transfers/quick_new rejects sources from other users" do
    other_user = User.create!(name: "Other", email: "quick_other@example.com", password: "password123")
    other_source = other_user.money_sources.create!(name: "Foreign", kind: "account")

    get quick_new_transfers_path(from_source_id: other_source.id, mode: "transfer")

    assert_redirected_to transfers_path
    assert flash[:alert].present?
  end

  test "GET /transfers/quick_new rejects mode/kind combinations the model does not allow" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")
    loan = @user.money_sources.create!(name: "Prestamo", kind: "loan", sub_kind: "personal")

    # withdraw needs the origin to be a non-cash payment source...
    get quick_new_transfers_path(from_source_id: cash.id, mode: "withdraw")
    assert_redirected_to transfers_path
    # ...and never offers cash advances from credit cards...
    get quick_new_transfers_path(from_source_id: card.id, mode: "withdraw")
    assert_redirected_to transfers_path
    # ...a pocket cannot receive from a debt source...
    get quick_new_transfers_path(from_source_id: card.id, mode: "pocket")
    assert_redirected_to transfers_path
    # ...and loans never pay out.
    get quick_new_transfers_path(from_source_id: loan.id, mode: "transfer")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: @savings.id, mode: "teleport")
    assert_redirected_to transfers_path
  end

  test "GET /transfers/quick_new withdraw redirects with an alert when no cash source exists" do
    get quick_new_transfers_path(from_source_id: @savings.id, mode: "withdraw")

    assert_redirected_to transfers_path
    assert flash[:alert].present?
  end

  # ----- Quick actions: advances, disbursements and pocket releases -----

  test "GET /transfers/quick_new advance from a credit card offers accounts and cash" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")
    wallet = @user.money_sources.create!(name: "Nequi", kind: "wallet")

    get quick_new_transfers_path(from_source_id: card.id, mode: "advance")

    assert_response :success
    assert_select "select[name='transfer[from_source_id]']", count: 0
    assert_select "input[name='transfer[from_source_id]'][value='#{card.id}']"
    options = css_select "select[name='transfer[to_source_id]'] option"
    values = options.map { |o| o["value"] }
    assert_includes values, @checking.id.to_s
    assert_includes values, wallet.id.to_s
    assert_includes values, cash.id.to_s, "a credit card advance can land on cash"
    refute_includes values, card.id.to_s, "the origin must not offer itself as destination"
  end

  test "quick advance POST raises the card debt without any expense" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: -1_000_000)

    assert_no_difference "Expense.count" do
      assert_difference "Transfer.count", 1 do
        post transfers_path, params: {
          quick: "1", mode: "advance", return_to: money_sources_credit_cards_path,
          transfer: { from_source_id: card.id, to_source_id: @checking.id, amount: 300_000, date: Date.current.to_s }
        }
      end
    end
    assert_redirected_to money_sources_credit_cards_path
    assert_equal BigDecimal("1_300_000"), card.reload.used_credit
    assert_equal BigDecimal("300_000"), @checking.reload.balance
  end

  test "GET /transfers/quick_new disburse from a revolving loan offers account destinations" do
    revolving = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving")
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")

    get quick_new_transfers_path(from_source_id: revolving.id, mode: "disburse")

    assert_response :success
    assert_select "input[name='transfer[from_source_id]'][value='#{revolving.id}']"
    options = css_select "select[name='transfer[to_source_id]'] option"
    values = options.map { |o| o["value"] }
    assert_includes values, @checking.id.to_s
    refute_includes values, card.id.to_s, "a disbursement is never a debt payment"
  end

  test "quick disburse POST raises the revolving outstanding without any expense" do
    revolving = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving", starting_balance: 0)
    revolving.create_credit_account!(outstanding_balance: 1_000_000)
    revolving.reload

    assert_no_difference "Expense.count" do
      assert_difference "Transfer.count", 1 do
        post transfers_path, params: {
          quick: "1", mode: "disburse", return_to: money_sources_credit_cards_path,
          transfer: { from_source_id: revolving.id, to_source_id: @checking.id, amount: 400_000, date: Date.current.to_s }
        }
      end
    end
    assert_redirected_to money_sources_credit_cards_path
    assert_equal BigDecimal("1_400_000"), revolving.reload.credit_account.outstanding_balance.to_d
    assert_equal BigDecimal("400_000"), @checking.reload.balance
  end

  test "GET /transfers/quick_new release from a pocket offers accounts and cash" do
    pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 500_000)
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")

    get quick_new_transfers_path(from_source_id: pocket.id, mode: "release")

    assert_response :success
    assert_select "input[name='transfer[from_source_id]'][value='#{pocket.id}']"
    options = css_select "select[name='transfer[to_source_id]'] option"
    values = options.map { |o| o["value"] }
    assert_includes values, @savings.id.to_s
    assert_includes values, cash.id.to_s, "pocket money can come back out as cash"
    refute_includes values, card.id.to_s, "a pocket can never fund a debt"
  end

  test "quick release POST moves pocket money out without any expense" do
    pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 500_000)

    assert_no_difference "Expense.count" do
      assert_difference "Transfer.count", 1 do
        post transfers_path, params: {
          quick: "1", mode: "release", return_to: money_sources_pockets_path,
          transfer: { from_source_id: pocket.id, to_source_id: @savings.id, amount: "200.000", date: Date.current.to_s }
        }
      end
    end
    assert_redirected_to money_sources_pockets_path
    assert_equal BigDecimal("300_000"), pocket.reload.balance
    assert_equal BigDecimal("201_000"), @savings.reload.balance
  end

  test "GET /transfers/quick_new rejects advance, disburse and release outside their origins" do
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")
    personal = @user.money_sources.create!(name: "Libre Inversión", kind: "loan", sub_kind: "personal")
    pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 0)

    get quick_new_transfers_path(from_source_id: @savings.id, mode: "advance")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: cash.id, mode: "advance")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: card.id, mode: "disburse")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: personal.id, mode: "disburse")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: @savings.id, mode: "release")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: card.id, mode: "release")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(from_source_id: pocket.id, mode: "transfer")
    assert_redirected_to transfers_path
  end

  # ----- Destination-anchored quick assign (pocket entry points) -----

  test "GET /transfers/quick_new assign fixes the pocket and offers non-debt payment origins" do
    pocket = @user.money_sources.create!(name: "Bolsillo", kind: "pocket", starting_balance: 0)
    cash = @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100)
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")

    get quick_new_transfers_path(to_source_id: pocket.id, mode: "assign")

    assert_response :success
    # Destination: the pocket, fixed (no selector, hidden field).
    assert_select "select[name='transfer[to_source_id]']", count: 0
    assert_select "input[name='transfer[to_source_id]'][value='#{pocket.id}']"
    # Origin: selectable, accounts + cash only, never a debt.
    origins = css_select "select[name='transfer[from_source_id]'] option"
    origin_values = origins.map { |o| o["value"] }
    assert_includes origin_values, @savings.id.to_s
    assert_includes origin_values, cash.id.to_s
    refute_includes origin_values, card.id.to_s, "a debt can never fund a pocket"
    # The optional goal step follows, like the pocket mode.
    assert_select "select[name='transfer[assign_goal_id]']", count: 1
  end

  test "quick assign POST into a pocket with a goal allocates the money" do
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 0)
    goal = Goal.create!(user: @user, pocket: pocket, name: "Viaje Europa", target_amount: 20_000_000)
    @savings.update!(starting_balance: 1_000_000)

    assert_difference([ "Transfer.count", "GoalAllocation.count" ], 1) do
      assert_no_difference "Expense.count" do
        post transfers_path, params: {
          quick: "1", mode: "assign", return_to: money_source_path(pocket),
          transfer: { from_source_id: @savings.id, to_source_id: pocket.id, amount: "700.000",
                      date: Date.current.to_s, assign_goal_id: goal.id }
        }
      end
    end
    assert_redirected_to money_source_path(pocket)
    allocation = GoalAllocation.last
    assert_equal goal, allocation.financial_goal
    assert_equal 700_000, allocation.amount
    assert_equal 700_000, pocket.reload.balance.to_i
  end

  test "GET /transfers/quick_new assign rejects non-pocket or missing destinations" do
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")

    get quick_new_transfers_path(to_source_id: @checking.id, mode: "assign")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(mode: "assign")
    assert_redirected_to transfers_path
    get quick_new_transfers_path(to_source_id: card.id, mode: "assign")
    assert_redirected_to transfers_path
  end

  test "GET /transfers/quick_new assign rejects pockets from other users" do
    other_user = User.create!(name: "Other", email: "assign_other@example.com", password: "password123")
    foreign_pocket = other_user.money_sources.create!(name: "Ajeno", kind: "pocket", starting_balance: 0)

    get quick_new_transfers_path(to_source_id: foreign_pocket.id, mode: "assign")

    assert_redirected_to transfers_path
    assert flash[:alert].present?
  end

  test "POST /transfers rejects an origin source owned by another user" do
    other_user = User.create!(name: "Other", email: "transfer_foreign_origin@example.com", password: "password123")
    foreign_source = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account", starting_balance: 1_000)
    balance_before = foreign_source.reload.cached_balance

    assert_no_difference "Transfer.count" do
      post transfers_path, params: { transfer: {
        from_source_id: foreign_source.id, to_source_id: @checking.id,
        amount: 100, date: Date.today.to_s
      } }
    end

    assert_redirected_to transfers_path
    assert flash[:alert].present?
    assert_equal balance_before, foreign_source.reload.cached_balance
  end

  test "POST /transfers rejects a destination source owned by another user" do
    other_user = User.create!(name: "Other", email: "transfer_foreign_destination@example.com", password: "password123")
    foreign_source = other_user.money_sources.create!(name: "Cuenta Ajena", kind: "account", starting_balance: 0)
    origin_before = @savings.reload.cached_balance
    destination_before = foreign_source.reload.cached_balance

    assert_no_difference "Transfer.count" do
      post transfers_path, params: { transfer: {
        from_source_id: @savings.id, to_source_id: foreign_source.id,
        amount: 100, date: Date.today.to_s
      } }
    end

    assert_redirected_to transfers_path
    assert flash[:alert].present?
    assert_equal origin_before, @savings.reload.cached_balance
    assert_equal destination_before, foreign_source.reload.cached_balance
  end
end
