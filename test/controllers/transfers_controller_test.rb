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

  test "GET /transfers/new renders the form" do
    get new_transfer_path
    assert_response :success
    assert_select "form"
    assert_select "select", minimum: 2
  end

  test "GET /transfers/new defaults the date to the current cycle start with a schedule" do
    @user.update!(financial_cycle_start_day: 20)
    expected = PayCycle.current(@user).starts

    get new_transfer_path

    assert_response :success
    assert_select "input[name='transfer[date]'][value=?]", expected.to_s
  end

  test "GET /transfers/new offers each operation only its allowed sources" do
    revolving = @user.money_sources.create!(name: "Rotativo", kind: "loan", sub_kind: "revolving")
    personal = @user.money_sources.create!(name: "Libre Inversión", kind: "loan", sub_kind: "personal")
    card = @user.money_sources.create!(name: "Visa", kind: "credit_card")

    get new_transfer_path
    assert_response :success

    # FROM: payment sources + revolving loans (disbursements only); loans
    # other than revolving never send money. Credit cards CAN send money —
    # they are payment sources.
    assert_select "select[name='transfer[from_source_id]'] option", text: /Savings/, count: 1
    assert_select "select[name='transfer[from_source_id]'] option", text: /Rotativo/, count: 1
    assert_select "select[name='transfer[from_source_id]'] option", text: /Visa/, count: 1
    assert_select "select[name='transfer[from_source_id]'] option", text: /Libre Inversión/, count: 0

    # TO: payment sources + credit cards + loans (payments on debt).
    assert_select "select[name='transfer[to_source_id]'] option", text: /Checking/, count: 1
    assert_select "select[name='transfer[to_source_id]'] option", text: /Visa/, count: 1
    assert_select "select[name='transfer[to_source_id]'] option", text: /Libre Inversión/, count: 1
    assert_select "select[name='transfer[to_source_id]'] option", text: /Rotativo/, count: 1
    assert personal.debt_payment_target?
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

  test "POST /transfers renders new on validation failure" do
    post transfers_path, params: {
      transfer: {
        from_source_id: @savings.id,
        to_source_id: @savings.id,
        amount: 100,
        date: Date.today.to_s
      }
    }
    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "DELETE /transfers/:id destroys the transfer" do
    transfer = create_transfer
    assert_difference "Transfer.count", -1 do
      delete transfer_path(transfer)
    end
    assert_redirected_to transfers_path
  end

  test "transfer affects balances correctly" do
    create_transfer(amount: 200)
    assert_equal BigDecimal("800"), @savings.reload.balance
    assert_equal BigDecimal("200"), @checking.reload.balance
  end

  test "user cannot delete other user's transfer" do
    other_user = User.create!(name: "Other", email: "other_transfer_ctrl@example.com", password: "password123")
    other_a = other_user.money_sources.create!(name: "A", kind: "account")
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
          quick: "1", mode: "withdraw", return_to: money_sources_path,
          transfer: { from_source_id: @savings.id, to_source_id: cash.id, amount: 100, date: Date.current.to_s }
        }
      end
    end
    assert_redirected_to money_sources_path
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

    assert_difference([ "Transfer.count", "GoalAllocation.count" ], 1) do
      assert_no_difference "Expense.count" do
        post transfers_path, params: {
          quick: "1", mode: "pocket", return_to: money_sources_path,
          transfer: { from_source_id: @savings.id, to_source_id: pocket.id, amount: "500.000",
                      date: Date.current.to_s, assign_goal_id: goal.id }
        }
      end
    end
    assert_redirected_to money_sources_path
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
end
