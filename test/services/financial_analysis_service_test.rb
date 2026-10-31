# frozen_string_literal: true

require "test_helper"

class FinancialAnalysisServiceTest < ActionCable::TestCase
  STREAM = "financial_chat_user_%{user_id}"

  setup do
    @user = User.create!(
      name: "Test User",
      email: "financial_analysis_test@example.com",
      password: "password123"
    )
    @chat = FinancialChat.for_user(@user)
    @question = @chat.messages.create!(role: "user", content: "¿Cuánto gasté este mes?", status: "sent")
    @fake = FakeAiProvider.new(responses: [])
  end

  def run_service(broadcast_interval: 0.0)
    fake = @fake
    stub_method(Ai::Providers, :strong, ->(**_kwargs) { fake }) do
      FinancialAnalysisService.new(
        chat_id: @chat.id, message_id: @question.id, broadcast_interval: broadcast_interval
      ).call
    end
  end

  def user_stream
    FinancialChatChannel.stream_name_for(@user)
  end

  def events_on_stream
    transmissions.map { |p| p["event"] }
  end

  test "broadcasts processing, deltas and completion, and persists the assistant answer" do
    @fake.responses << { content: "Gastaste **COP 17.800.000** este mes.", output_tokens: 42, input_tokens: 100 }

    run_service

    events = events_on_stream
    assert_equal %w[assistant_processing assistant_delta assistant_completed], events.uniq

    answer = @chat.messages.reload.where(role: "assistant").sole
    assert_equal "Gastaste **COP 17.800.000** este mes.", answer.content
    assert_equal "complete", answer.status
    assert_equal "fake-model", answer.model
    assert_equal 42, answer.output_tokens
  end

  test "completed event carries the rendered HTML answer" do
    @fake.responses << { content: "Gastaste **COP 17.800.000**" }

    run_service

    payload = transmissions.find { |p| p["event"] == "assistant_completed" }
    assert_includes payload.dig("message", "content"), "<strong>COP 17.800.000</strong>"
    assert_equal "assistant", payload.dig("message", "role")
  end

  test "delta events carry incremental text" do
    @fake.responses << { content: "Primera parte. Segunda parte." }

    run_service

    deltas = transmissions.select { |p| p["event"] == "assistant_delta" }
                          .map { |p| p["delta"] }
    assert_equal "Primera parte. Segunda parte.", deltas.join
  end

  test "sends the system prompt with financial context, history and the question" do
    @fake.responses << { content: "ok" }
    prior_answer = @chat.messages.create!(role: "assistant", content: "Respuesta previa", status: "complete")
    prior_answer.update_column(:created_at, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
    @question.update_column(:created_at, 30.seconds.ago) # rubocop:disable Rails/SkipsModelValidations

    run_service

    messages = @fake.calls.sole
    assert_equal "system", messages.first[:role]
    system_prompt = messages.first[:content]
    assert_match(/analista financiero/i, system_prompt)
    assert_match(/COP/, system_prompt)

    history = messages[1..]
    assert_equal "Respuesta previa", history.first[:content]
    assert_equal "¿Cuánto gasté este mes?", history.last[:content]
  end

  test "the system prompt names the application using APP_NAME" do
    @fake.responses << { content: "ok" }

    with_env("APP_NAME" => "Mis Gastos") do
      run_service
    end

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt, "(Mis Gastos)"
    refute_includes system_prompt, "MyExpenses"
  end

  test "the system prompt falls back to the default application name when APP_NAME is missing" do
    @fake.responses << { content: "ok" }

    with_env("APP_NAME" => nil) do
      run_service
    end

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt, "(Yogasto)"
  end

  test "includes expense, income and budget data in the system prompt" do
    @fake.responses << { content: "ok" }
    category = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @user.expenses.create!(amount: 85_000, date: Date.today, category: category, description: "Almuerzo",
                           money_source: source)
    @user.incomes.create!(amount: 4_500_000, date: Date.today, category: income_category, description: "Salario",
                          money_source: source)
    @user.budgets.create!(category: category, monthly_amount: 500_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Restaurantes/, system_prompt)
    assert_match(/85\.000/, system_prompt)
    assert_match(/4\.500\.000/, system_prompt)
    assert_match(/500\.000/, system_prompt)
  end

  test "includes active budgets with remaining, percentage and status" do
    @fake.responses << { content: "ok" }
    category = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    inactive_category = Category.create!(name: "Presupuesto inactivo", is_default: true, category_type: "expense")
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @user.expenses.create!(amount: 85_000, date: Date.today, category: category, description: "Almuerzo",
                           money_source: source)
    @user.expenses.create!(amount: 20_000, date: Date.today, category: inactive_category, description: "Otro",
                           money_source: source)
    @user.budgets.create!(category: category, monthly_amount: 100_000)
    @user.budgets.create!(category: inactive_category, monthly_amount: 50_000, active: false)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt,
                    "- Restaurantes: gastado COP 85.000 de COP 100.000 (85%); " \
                    "restante COP 15.000; estado Cerca del límite"
    refute_includes system_prompt, "Presupuesto inactivo: gastado"
  end

  test "reports over-budget spending with the exceeded amount and status" do
    @fake.responses << { content: "ok" }
    category = Category.create!(name: "Ocio", is_default: true, category_type: "expense")
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @user.expenses.create!(amount: 120_000, date: Date.today, category: category, description: "Salida",
                           money_source: source)
    @user.budgets.create!(category: category, monthly_amount: 100_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt,
                    "- Ocio: gastado COP 120.000 de COP 100.000 (120%); " \
                    "excedido COP 20.000; estado Superado"
  end

  test "includes goals in progress ordered by priority with progress and required contribution" do
    @fake.responses << { content: "ok" }
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 10_000_000)
    high = @user.goals.create!(name: "Viaje", pocket: pocket, target_amount: 5_000_000,
                               target_date: Date.current + 8.months, priority: 2, category: "travel")
    low = @user.goals.create!(name: "Computador", pocket: pocket, target_amount: 1_000_000,
                              priority: 0, category: "other")
    GoalAllocation.create!(financial_goal: high, amount: 2_000_000, date: Date.current)
    GoalAllocation.create!(financial_goal: low, amount: 100_000, date: Date.current)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Metas de ahorro en curso:/, system_prompt)
    assert_includes system_prompt,
                    "- Viaje (Viaje; prioridad alta; bolsillo Ahorros): " \
                    "ahorrado COP 2.000.000 de COP 5.000.000 (40%); restante COP 3.000.000; " \
                    "fecha límite #{I18n.l(high.target_date, format: :long)}; faltan 8 meses; " \
                    "aporte requerido COP 375.000/mes; estado En rumbo"
    assert_includes system_prompt, "- Computador (Otra; prioridad baja; bolsillo Ahorros)"
    assert_operator system_prompt.index("Viaje"), :<, system_prompt.index("Computador")
    assert_includes system_prompt,
                    "Total metas en curso: 2 · ahorrado COP 2.100.000 · " \
                    "objetivo COP 6.000.000 · restante COP 3.900.000"
  end

  test "excludes completed, archived and other users' goals from the system prompt" do
    @fake.responses << { content: "ok" }
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 10_000_000)
    @user.goals.create!(name: "Meta propia", pocket: pocket, target_amount: 3_000_000)
    completed = @user.goals.create!(name: "Meta cumplida", pocket: pocket, target_amount: 1_000_000)
    @user.goals.create!(name: "Meta archivada", pocket: pocket, target_amount: 2_000_000, status: "archived")
    GoalAllocation.create!(financial_goal: completed, amount: 1_000_000, date: Date.current)

    other_user = User.create!(name: "Other", email: "other_goals@example.com", password: "password123")
    other_pocket = other_user.money_sources.create!(name: "Ahorros ajenos", kind: "pocket",
                                                    starting_balance: 2_000_000)
    other_user.goals.create!(name: "Meta ajena", pocket: other_pocket, target_amount: 1_000_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt, "Meta propia"
    refute_includes system_prompt, "Meta cumplida"
    refute_includes system_prompt, "Meta archivada"
    refute_includes system_prompt, "Meta ajena"
  end

  test "keeps goals without a target date explicit instead of inventing a date or contribution" do
    @fake.responses << { content: "ok" }
    pocket = @user.money_sources.create!(name: "Ahorros", kind: "pocket", starting_balance: 2_000_000)
    @user.goals.create!(name: "Fondo libre", pocket: pocket, target_amount: 2_000_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt,
                    "- Fondo libre (Sin categoría; prioridad media; bolsillo Ahorros): " \
                    "ahorrado COP 0 de COP 2.000.000 (0%); restante COP 2.000.000; " \
                    "fecha límite sin fecha; aporte requerido sin dato; estado En rumbo"
  end

  test "goal and budget instructions tell the assistant to use those blocks" do
    @fake.responses << { content: "ok" }

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Metas de ahorro en curso/, system_prompt)
    assert_match(/Presupuestos del periodo/, system_prompt)
  end

  test "includes pending recurring expenses and their total in the system prompt" do
    @fake.responses << { content: "ok" }
    category = Category.create!(name: "Servicios", is_default: true, category_type: "expense")
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    RecurringTemplate.create!(user: @user, category: category, kind: "expense", amount: 100_000,
                             frequency: "monthly", payment_day: 28, active: true,
                             description: "Internet", money_source: source)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Internet/, system_prompt)
    assert_match(/100\.000/, system_prompt)
    assert_match(/pendientes/i, system_prompt)
  end

  test "includes bank account and cash balances in the system prompt" do
    @fake.responses << { content: "ok" }
    @user.money_sources.create!(name: "Davivienda", kind: "account", starting_balance: 500_000)
    @user.money_sources.create!(name: "Débito BBVA", kind: "debit_card", starting_balance: 300_000)
    @user.money_sources.create!(name: "Nequi", kind: "wallet", starting_balance: 50_000)
    @user.money_sources.create!(name: "Efectivo", kind: "cash", starting_balance: 100_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Saldo en cuentas bancarias.*COP 850\.000/, system_prompt)
    assert_match(/Efectivo en mano.*COP 100\.000/, system_prompt)
    assert_includes system_prompt, "Davivienda"
    assert_includes system_prompt, "Nequi"
  end

  test "bank and cash balances use the reconciled balance and exclude inactive, savings and debt sources" do
    @fake.responses << { content: "ok" }
    account = @user.money_sources.create!(name: "Cuenta activa", kind: "account", starting_balance: 400_000)
    account.update!(balance_offset: 40_000)
    @user.money_sources.create!(name: "Cuenta inactiva", kind: "account", starting_balance: 900_000, active: false)
    @user.money_sources.create!(name: "Bolsillo viaje", kind: "pocket", starting_balance: 700_000)
    @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: -8_000_000)
    @user.money_sources.create!(name: "Hipotecario", kind: "loan", starting_balance: -1_000_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Saldo en cuentas bancarias.*COP 440\.000/, system_prompt)
    refute_match(/Efectivo en mano.*COP [1-9]/, system_prompt)
    refute_includes system_prompt, "Cuenta inactiva"
    refute_includes system_prompt, "Bolsillo viaje"
  end

  test "credit card debt uses the reconciled used_credit instead of the cached balance" do
    @fake.responses << { content: "ok" }
    visa = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: -100_000)
    visa.update!(balance_offset: 25_000)
    paid = @user.money_sources.create!(name: "Nu", kind: "credit_card", starting_balance: -50_000)
    paid.update!(balance_offset: 50_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Tarjetas de crédito \(deuda actual\)/, system_prompt)
    assert_match(/Visa: COP 75\.000/, system_prompt)
    assert_match(/Nu: COP 0/, system_prompt)
    refute_includes system_prompt, "Visa: COP 100.000"
  end

  test "includes loan details with total value, type, balance, rate, installment and progress in the system prompt" do
    @fake.responses << { content: "ok" }
    loan = @user.money_sources.create!(name: "Hipotecario", kind: "loan", sub_kind: "mortgage",
                                       bank: "Banco Central")
    loan.create_credit_account!(
      principal_amount: 120_000_000,
      outstanding_balance: 80_000_000,
      interest_rate: 10.5,
      interest_rate_type: "effective_annual",
      installment_amount: 1_500_000,
      installment_count: 120,
      installments_paid: 24,
      payment_frequency: "monthly"
    )

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Créditos y préstamos:/, system_prompt)
    assert_includes system_prompt,
                    "- Hipotecario (Crédito hipotecario; Banco Central): " \
                    "valor total COP 120.000.000; saldo COP 80.000.000; " \
                    "interés 10.50% EA; cuota COP 1.500.000 mensual; " \
                    "cuota actual 25 de 120; cuotas faltantes 80"
    assert_match(/Total saldo de créditos: COP 80\.000\.000/, system_prompt)
  end

  test "excludes inactive loans and other users' loans from the credit context" do
    @fake.responses << { content: "ok" }
    other_user = User.create!(name: "Other", email: "other_financial_chat@example.com", password: "password123")
    active_loan = @user.money_sources.create!(name: "Crédito activo", kind: "loan", sub_kind: "personal")
    active_loan.create_credit_account!(principal_amount: 10_000_000, outstanding_balance: 4_000_000)
    inactive_loan = @user.money_sources.create!(name: "Crédito inactivo", kind: "loan", active: false)
    inactive_loan.create_credit_account!(principal_amount: 90_000_000, outstanding_balance: 90_000_000)
    other_loan = other_user.money_sources.create!(name: "Crédito ajeno", kind: "loan")
    other_loan.create_credit_account!(principal_amount: 70_000_000, outstanding_balance: 70_000_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt, "Crédito activo"
    refute_includes system_prompt, "Crédito inactivo"
    refute_includes system_prompt, "Crédito ajeno"
    assert_match(/Total saldo de créditos: COP 4\.000\.000/, system_prompt)
  end

  test "marks missing loan data as unavailable instead of inventing figures" do
    @fake.responses << { content: "ok" }
    @user.money_sources.create!(name: "Crédito sin detalles", kind: "loan")

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt,
                    "- Crédito sin detalles (Préstamo): valor total sin dato; saldo sin dato; " \
                    "interés sin tasa registrada; cuota sin cuota registrada; " \
                    "cuota actual sin dato; cuotas faltantes sin dato"
  end

  test "credit instructions require every active credit and keep revolving separate from cards" do
    @fake.responses << { content: "ok" }
    revolving = @user.money_sources.create!(name: "Crédito Rotativo", kind: "loan", sub_kind: "revolving")
    revolving.create_credit_account!(principal_amount: 50_000_000, outstanding_balance: 20_000_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_includes system_prompt, "Crédito Rotativo (Crédito rotativo"
    assert_match(/incluye todos los créditos\s+activos/i, system_prompt)
    assert_match(/no es una tarjeta de crédito/i, system_prompt)
    assert_match(/corrige explícitamente/i, system_prompt)
  end

  test "system prompt states that current data overrides figures from earlier answers" do
    @fake.responses << { content: "ok" }

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/fuente de verdad/i, system_prompt)
    assert_match(/respuestas anteriores/i, system_prompt)
  end

  test "uses the financial cycle for the reporting period when cycles are enabled" do
    @user.update!(financial_cycle_start_day: 20)
    @fake.responses << { content: "ok" }
    current_cycle = PayCycle.current(@user)
    previous_cycle = PayCycle.previous(@user)
    category = Category.create!(name: "Mercado", is_default: true, category_type: "expense")
    income_category = Category.create!(name: "Salario", is_default: true, category_type: "income")
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @user.expenses.create!(amount: 40_000, date: current_cycle.starts, category: category, description: "Ciclo",
                           money_source: source)
    @user.expenses.create!(amount: 25_000, date: previous_cycle.starts, category: category, description: "Anterior",
                           money_source: source)
    @user.incomes.create!(amount: 900_000, date: current_cycle.starts, category: income_category, description: "Pago",
                          money_source: source)
    @user.budgets.create!(category: category, monthly_amount: 100_000)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    assert_match(/Ciclo financiero actual: #{Regexp.escape(current_cycle.label)} \(.+\)/, system_prompt)
    assert_match(/Ciclo financiero anterior: #{Regexp.escape(previous_cycle.label)}/, system_prompt)
    assert_match(/Ingresos #{Regexp.escape(current_cycle.label)}: COP 900\.000/, system_prompt)
    assert_match(/Gastos #{Regexp.escape(current_cycle.label)}: COP 40\.000/, system_prompt)
    assert_match(/Gastos #{Regexp.escape(previous_cycle.label)}: COP 25\.000/, system_prompt)
    assert_match(/Mercado: gastado COP 40\.000 de COP 100\.000/, system_prompt)
  end

  test "keeps calendar months when financial cycles are disabled" do
    @user.update!(financial_cycle_start_day: 1)
    @fake.responses << { content: "ok" }
    category = Category.create!(name: "Mercado", is_default: true, category_type: "expense")
    source = @user.money_sources.create!(name: "Cuenta", kind: "account", starting_balance: 1_000_000)
    @user.expenses.create!(amount: 30_000, date: Time.zone.today, category: category, description: "Mes",
                           money_source: source)

    run_service

    system_prompt = @fake.calls.sole.first[:content]
    month_label = I18n.l(Time.zone.today, format: "%b %Y")
    assert_match(/Mes actual: #{Regexp.escape(month_label)}/, system_prompt)
    assert_match(/Mes anterior: #{Regexp.escape(I18n.l(Time.zone.today.prev_month, format: "%b %Y"))}/, system_prompt)
    assert_match(/Gastos #{Regexp.escape(month_label)}: COP 30\.000/, system_prompt)
    refute_match(/Ciclo financiero/, system_prompt)
  end

  test "provider failure broadcasts assistant_failed and persists nothing" do
    @fake.responses << Ai::Provider::Error.new("LLM timeout")

    run_service

    events = events_on_stream
    assert_includes events, "assistant_failed"
    assert_not_includes events, "assistant_completed"
    assert_equal 0, @chat.messages.reload.where(role: "assistant").count
  end

  test "provider failure records the error in AiRequest" do
    @fake.responses << Ai::Provider::Error.new("LLM timeout")

    run_service

    request = AiRequest.order(:created_at).last
    assert_equal "financial_chat", request.task
    assert_equal "strong_ai", request.strategy
    assert_equal "error", request.status
    assert_match(/LLM timeout/, request.error)
  end

  test "success records the strong_ai usage in AiRequest" do
    @fake.responses << { content: "ok", output_tokens: 30, input_tokens: 100 }

    run_service

    request = AiRequest.order(:created_at).last
    assert_equal "ok", request.status
    assert_equal 30, request.output_tokens
    assert request.latency_ms.present?
  end

  test "missing message or assistant message is a no-op" do
    assert_nothing_raised do
      FinancialAnalysisService.new(chat_id: @chat.id, message_id: 999_999).call
    end
  end

  test "strong tier disabled flag does not block the chat" do
    @fake.responses << { content: "ok", output_tokens: 5, input_tokens: 10 }

    with_env({ "AI_DISABLE_STRONG_TIER" => "true" }) do
      run_service
    end

    assert_includes events_on_stream, "assistant_completed"
    assert_equal 1, @chat.messages.reload.where(role: "assistant").count
    assert_equal "strong_ai", AiRequest.order(:created_at).last.strategy
  end

  test "unconfigured provider broadcasts assistant_failed" do
    stub_method(Ai::Providers, :strong, ->(**_kwargs) { nil }) do
      FinancialAnalysisService.new(chat_id: @chat.id, message_id: @question.id).call
    end

    assert_includes events_on_stream, "assistant_failed"
    assert_equal 0, @chat.messages.reload.where(role: "assistant").count
  end

  private

  def payloads
    broadcasts(user_stream).map { |message| message.is_a?(String) ? JSON.parse(message) : message }
  end

  def transmissions
    payloads.select { |p| p["user_message_id"] == @question.id }
  end

  def events_on_stream
    transmissions.map { |p| p["event"] }
  end
end
