# frozen_string_literal: true

require_relative "financial_chat_markdown_renderer"

# Streams a LLM answer for a financial chat question through Action Cable
# and persists the final assistant message.
#
#   FinancialChatJob -> FinancialAnalysisService.new(chat_id:, message_id:).call
#
# Uses the strong AI tier (Ai::Providers.strong) bypassing Ai::Router: chat
# is a free-text streaming conversation, not a structured extraction task.
# The strong tier is used even when AI_DISABLE_STRONG_TIER is set: that flag
# is a cost guard for the structured Router tasks, while chat answers demand
# the best available model.
#
# Broadcast events on FinancialChatChannel (all anchored with
# user_message_id):
#   assistant_processing  - show the "Analyzing your finances..." placeholder
#   assistant_delta       { delta }   - incremental answer text
#   assistant_completed   { message } - final answer (client_payload)
#   assistant_failed      { error }   - inline error; client offers retry
class FinancialAnalysisService
  # Deltas are buffered and flushed at most once per interval (seconds) or
  # when the buffer grows past MAX_BUFFER_CHARS, keeping Solid Cable writes
  # low while the answer still feels streamed.
  DEFAULT_BROADCAST_INTERVAL = 0.25
  MAX_BUFFER_CHARS = 200
  # Kinds holding money the user can spend from a bank: accounts, their debit
  # cards and digital wallets. Cash has its own block; pockets are assigned
  # savings and never count as immediately available money.
  BANK_KINDS = %w[account debit_card wallet].freeze
  CASH_KINDS = %w[cash].freeze

  def initialize(chat_id:, message_id:, broadcast_interval: DEFAULT_BROADCAST_INTERVAL)
    @chat = FinancialChat.find_by(id: chat_id)
    @message = @chat && FinancialChatMessage.find_by(id: message_id)
    @broadcast_interval = broadcast_interval
    @user = @chat&.user
  end

  def call
    return unless applicable?

    @provider = Ai::Providers.strong
    return fail_analysis("El asistente de IA no está configurado.") unless @provider&.configured?

    answer
  end

  private

  def applicable?
    return false unless @message

    @message.user? && @message.status == "sent" && !already_answered?
  end

  # Retried job after a completed run would duplicate the answer.
  def already_answered?
    @chat.messages.where(role: "assistant").where("created_at >= ?", @message.created_at).exists?
  end

  def answer
    broadcast("assistant_processing")

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    content = +""
    buffer = DeltaBuffer.new(@broadcast_interval) { |text| broadcast("assistant_delta", delta: text) }

    response = @provider.chat_stream(messages: llm_messages) do |delta|
      content << delta
      buffer.push(delta)
    end
    buffer.drain
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    Ai::Recorder.record(
      task: :financial_chat, user: @user, strategy: "strong_ai", provider: @provider,
      input_tokens: positive(response.input_tokens), output_tokens: positive(response.output_tokens),
      latency_ms: latency_ms, prompt: llm_messages, output: content
    )

    persist_answer(content: content, response: response, latency_ms: latency_ms)
    broadcast("assistant_completed", message: answer_message.client_payload)
  rescue Ai::Provider::Error => e
    fail_analysis(e.message)
  end

  def answer_message
    @chat.messages.reload.where(role: "assistant").order(:created_at).last
  end

  def persist_answer(content:, response:, latency_ms:)
    FinancialChatMessage.create!(
      financial_chat: @chat,
      role: "assistant",
      content: content,
      status: "complete",
      model: response.model,
      input_tokens: positive(response.input_tokens),
      output_tokens: positive(response.output_tokens),
      latency_ms: latency_ms
    )
  end

  def positive(value)
    value.to_i.positive? ? value : nil
  end

  def fail_analysis(error)
    Ai::Recorder.record(task: :financial_chat, user: @user, strategy: "strong_ai",
                        provider: nil, status: "error", error: error)
    broadcast("assistant_failed", error: error)
  end

  def broadcast(event, **payload)
    FinancialChatChannel.broadcast(@user, { event: event, user_message_id: @message.id }.merge(payload))
  end

  def llm_messages
    [ { role: "system", content: system_prompt } ] + @chat.conversation_history +
      [ { role: "user", content: @message.content } ]
  end

  def system_prompt
    <<~PROMPT
      Eres el analista financiero personal del usuario dentro de su aplicación de gastos
      (MyExpenses). Respondes preguntas sobre sus gastos, ingresos, categorías,
      presupuestos, deudas y patrones de gasto usando ÚNICAMENTE los datos que se
      entregan a continuación.

      DATOS DEL USUARIO
      #{financial_context}

      REGLAS
      - Responde siempre en español, de forma breve, clara y profesional.
      - Usa solo los datos entregados; si falta información, dilo sin inventar cifras.
      - Los DATOS DEL USUARIO son la fuente de verdad y están actualizados al momento
        de esta pregunta: si respuestas anteriores de la conversación muestran cifras
        distintas (por ejemplo, deudas ya pagadas), usa los datos actuales y no
        repitas las cifras viejas.
      - Respeta el periodo indicado en los DATOS DEL USUARIO: si es un ciclo
        financiero, habla de "ciclo" y usa sus fechas; si es un mes calendario,
        habla de "mes".
      - Formato de dinero: COP 1.234.567 (sin decimales).
      - Escribe markdown: párrafos cortos, listas cuando ayuden, y **negrilla** en las cifras clave.
      - Cuando un resumen numérico compacto ayude, añade UNA tarjeta insight:

        ```insight
        {"title": "Gasto mensual", "value": "COP 4.820.000", "delta": "+8.4% vs. mes anterior"}
        ```

        Claves válidas: title, value, delta, detail, rows (lista de {label, value}).
      - Cierra con una sugerencia concreta o una pregunta de seguimiento cuando aporte valor.
    PROMPT
  end

  # Calendar month by default; the user's financial cycle when configured,
  # mirroring the dashboard: Reports::Period resolves this_month/last_month
  # to their pay-cycle equivalents (this_cycle/last_cycle).
  def financial_context
    current = reporting_period("this_month")
    previous = reporting_period("last_month")

    <<~CONTEXT
      #{period_header(current, :current)}
      #{period_header(previous, :previous)}

      Ingresos #{current.label}: #{money(Income.dashboard_summary(user: @user, range: current.range)[:total_amount])}
      Ingresos #{previous.label}: #{money(Income.dashboard_summary(user: @user, range: previous.range)[:total_amount])}

      Gastos #{current.label}: #{money(expense_total(current.range))}
      Gastos #{previous.label}: #{money(expense_total(previous.range))}

      Gastos por categoría (#{current.label}):
      #{category_lines(current.range)}

      Presupuestos del periodo:
      #{budget_lines(current.range)}

      #{bank_account_lines}

      #{cash_lines}

      Tarjetas de crédito (deuda actual):
      #{credit_card_lines}

      Gastos recurrentes pendientes de pago:
      #{recurring_pending_lines}
    CONTEXT
  end

  # The reporting period follows the dashboard: a pay cycle when the user
  # configured one, a calendar month otherwise.
  def reporting_period(preset)
    Reports::Period.new(preset: preset, user: @user)
  end

  def period_header(period, position)
    noun = position == :previous ? "anterior" : "actual"
    return "Mes #{noun}: #{period.label}" unless period.cycle_aligned?

    "Ciclo financiero #{noun}: #{period.label} (#{period_range_label(period)})"
  end

  def period_range_label(period)
    "#{I18n.l(period.range.begin, format: "%b %e").squeeze(" ").strip} – " \
      "#{I18n.l(period.range.end, format: "%b %e").squeeze(" ").strip}"
  end

  # Expenses are stored as negative amounts; the dashboard and this context
  # report the positive magnitude so the assistant never says "gastaste -X".
  def expense_total(period_range)
    Expense.dashboard_summary(user: @user, range: period_range)[:total_amount].to_d.abs
  end

  def category_lines(period_range)
    by_category = Expense.dashboard_summary(user: @user, range: period_range)[:by_category]
    return "- (sin gastos registrados)" if by_category.blank?

    by_category.sort_by { |_, total| -total.abs }
               .first(10)
               .map { |name, total| "- #{name}: #{money(total)}" }
               .join("\n")
  end

  def budget_lines(period_range)
    budgets = @user.budgets.includes(:category)
    return "- (sin presupuestos)" if budgets.blank?

    budgets.map do |budget|
      spent = CategorySpend.call(user: @user, category: budget.category, range: period_range)
      "- #{budget.category.name}: gastado #{money(spent)} de #{money(budget.monthly_amount)}"
    end.join("\n")
  end

  # Card debt is the reconciled, canonical figure the rest of the app shows:
  # used_credit is the outstanding balance including balance_offset, so it
  # reflects reconciliation adjustments and recorded payments. cached_balance
  # alone would surface stale pre-reconciliation numbers.
  def credit_card_lines
    cards = @user.money_sources.where(kind: "credit_card", active: true)
    return "- (sin tarjetas de crédito registradas)" if cards.blank?

    lines = cards.sort_by { |card| card.name.downcase }
                 .map { |card| "- #{card.name}: #{money(card.used_credit)}" }
    lines << "Total deuda tarjetas de crédito: #{money(cards.sum { |card| card.used_credit.to_d })}"
    lines.join("\n")
  end

  # Immediately available money held at a bank: the requested total on the
  # header line plus one line per active source so the assistant can answer
  # about a specific account too.
  def bank_account_lines
    liquid_lines(BANK_KINDS, "Saldo en cuentas bancarias (cuentas, tarjetas débito y billeteras)",
                 "- (sin cuentas bancarias registradas)")
  end

  def cash_lines
    liquid_lines(CASH_KINDS, "Efectivo en mano", "- (sin efectivo registrado)")
  end

  def liquid_lines(kinds, label, empty_line)
    sources = active_sources.select { |source| kinds.include?(source.kind) }
    lines = [ "#{label}: #{money(sources.sum { |source| source.balance.to_d })}" ]
    if sources.empty?
      lines << empty_line
    else
      sources.sort_by { |source| source.name.downcase }.each do |source|
        lines << "- #{source.name} (#{kind_label(source)}): #{money(source.balance)}"
      end
    end
    lines.join("\n")
  end

  def active_sources
    @active_sources ||= @user.money_sources.active.to_a
  end

  def kind_label(source)
    I18n.t("kinds.#{source.kind}", default: source.kind.titleize)
  end

  def recurring_pending_lines
    report = Reports::AvailableCycle.new(user: @user).call
    expenses = report[:pending_expenses]
    return "- (sin gastos recurrentes pendientes)" if expenses.blank?

    lines = expenses.map { |expense| "- #{expense[:name]}: #{money(expense[:missing])}" }
    lines << "Total gastos recurrentes pendientes: #{money(report[:pending_total])}"
    lines.join("\n")
  end

  # COP has no practical use for cents in this snapshot; whole pesos match
  # the format the prompt asks the assistant to use.
  def money(value)
    "COP #{ActiveSupport::NumberHelper.number_to_delimited(value.to_d.round)}"
  end

  # Buffers streamed deltas and flushes them through the given callback at
  # most once per interval (or past MAX_BUFFER_CHARS), reducing broadcast
  # volume without delaying the answer noticeably.
  class DeltaBuffer
    def initialize(interval, &callback)
      @interval = interval
      @callback = callback
      @buffer = +""
      @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def push(delta)
      @buffer << delta
      drain if due?
    end

    def drain
      return if @buffer.empty?

      @callback.call(@buffer.dup)
      @buffer = +""
      @last_flush = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    private

    def due?
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @buffer.length >= MAX_BUFFER_CHARS || now - @last_flush >= @interval
    end
  end
end
