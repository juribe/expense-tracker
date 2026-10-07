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

  # Compact text snapshot of the user's finances for the current month and
  # the previous one. Built from the same summaries the dashboard uses.
  def financial_context
    month = Time.zone.today
    previous = month << 1

    <<~CONTEXT
      Mes actual: #{I18n.l(month, format: :long, default: month.strftime("%B %Y"))}

      Ingresos #{month.strftime("%Y-%m")}: #{money(Income.dashboard_summary(user: @user, month: month)[:total_amount])}
      Ingresos #{previous.strftime("%Y-%m")}: #{money(Income.dashboard_summary(user: @user, month: previous)[:total_amount])}

      Gastos #{month.strftime("%Y-%m")}: #{money(Expense.dashboard_summary(user: @user, month: month)[:total_amount])}
      Gastos #{previous.strftime("%Y-%m")}: #{money(Expense.dashboard_summary(user: @user, month: previous)[:total_amount])}

      Gastos por categoría (#{month.strftime("%Y-%m")}):
      #{category_lines(month)}

      Presupuestos del mes:
      #{budget_lines(month)}

      Tarjetas de crédito (saldo actual):
      #{credit_card_lines}
    CONTEXT
  end

  def category_lines(month)
    by_category = Expense.dashboard_summary(user: @user, month: month)[:by_category]
    return "- (sin gastos registrados)" if by_category.blank?

    by_category.sort_by { |_, total| -total.abs }
               .first(10)
               .map { |name, total| "- #{name}: #{money(total)}" }
               .join("\n")
  end

  def budget_lines(month)
    budgets = @user.budgets.includes(:category)
    return "- (sin presupuestos)" if budgets.blank?

    budgets.map do |budget|
      spent = CategorySpend.call(user: @user, category: budget.category, month: month)
      "- #{budget.category.name}: gastado #{money(spent)} de #{money(budget.monthly_amount)}"
    end.join("\n")
  end

  def credit_card_lines
    cards = @user.money_sources.where(kind: "credit_card", active: true)
    return "- (sin tarjetas de crédito registradas)" if cards.blank?

    cards.map { |card| "- #{card.name}: #{money(card.cached_balance)}" }.join("\n")
  end

  def money(value)
    "COP #{ActiveSupport::NumberHelper.number_to_delimited(value.to_d)}"
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
