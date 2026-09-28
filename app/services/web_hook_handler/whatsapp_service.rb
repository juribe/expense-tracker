# frozen_string_literal: true

# WebHookHandler::WhatsappService
# Routes incoming WhatsApp Cloud API webhook payloads. CONNECT commands are
# delegated to Whatsapp::ConnectService (account linking); every other text
# message resolves the user through the active WhatsappConnection (via the
# permanent WhatsappIdentity) and feeds the standard expense ingestion
# pipeline. Messages from unconnected numbers get connection instructions and
# never create expenses.
#
# Example: WebHookHandler::WhatsappService.call(raw_body: request.raw_post)
module WebHookHandler
  class WhatsappService
    def self.call(raw_body:)
      new(raw_body: raw_body).call
    end

    def initialize(raw_body:)
      @raw_body = raw_body
    end

    def call
      payload = WhatsappPayload.new(@raw_body)
      return unless payload.object == "whatsapp_business_account"

      events = payload.message_events.to_a
      Rails.logger.info "[WhatsappService] Webhook received: #{events.size} event(s)"
      events.each do |event|
        # WhatsApp re-delivers webhooks on timeouts; claim by message id so
        # duplicates and concurrent jobs are idempotent.
        unless WhatsappInboundMessage.claim!(event.mid)
          Rails.logger.info "[WhatsappService] Duplicate delivery ignored: #{event.mid}"
          next
        end

        Rails.logger.info "[WhatsappService] Inbound event mid=#{event.mid} sender=#{event.sender_id} " \
                          "type=#{event.message.type} text=#{event.text.to_s.strip[0, 80].inspect}"

        if connect_command?(event)
          Rails.logger.info "[WhatsappService] CONNECT command from #{event.sender_id}"
          Whatsapp::ConnectService.call(event: event)
        else
          process_message(event)
        end
      rescue StandardError => e
        # Nothing may fail in silence: the user always learns that something
        # went wrong (duplicate deliveries stay deduped by mid).
        Rails.logger.error "[WhatsappService] Message #{event.mid} failed: #{e.class}: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        notify_failure(event.sender_id)
      end
    rescue JSON::ParserError => e
      Rails.logger.error "[WhatsappService] Invalid payload: #{e.message}"
    end

    private

    def notify_failure(phone_number)
      Whatsapp::ReplySender.send_to(
        phone_number,
        "Ups, tuve un problema procesando tu mensaje. Inténtalo de nuevo 🙏"
      )
    rescue StandardError => e
      Rails.logger.error "[WhatsappService] Failure notice could not be delivered: #{e.message}"
    end

    def connect_command?(event)
      event.message? && event.text.to_s.match?(/\A\s*CONNECT\s+\S+/i)
    end

    def process_message(event)
      user = resolve_user(event.sender_id)
      Rails.logger.info "[WhatsappService] User resolved: #{user ? "id=#{user.id}" : 'unconnected'} " \
                        "(sender=#{event.sender_id})"

      unless user
        Rails.logger.info "[WhatsappService] Unconnected number #{event.sender_id}; sending connect instructions"
        Whatsapp::ReplySender.send_to(
          event.sender_id,
          "Hola 👋 Conecta tu WhatsApp desde Configuración → WhatsApp del Expense Tracker para registrar gastos por este chat."
        )
        return
      end

      # A pending clarification consumes the message unless the resolver
      # detected a brand-new expense fragment in the reply; that fragment is
      # parsed by the normal pipeline (which already returns ARRAYS) while
      # the pending session and its candidates stay untouched.
      if (session = user.expense_clarifications.pending.order(:updated_at).last)
        Rails.logger.info "[WhatsappService] Pending clarification session=#{session.id}; routing reply there"
        outcome, new_expense_text = route_to_clarification(user, event, session)
        if outcome == :new_expense_fragment
          input = Expenses::Input.from_params("text", { text: new_expense_text })
          return run_pipeline(user, event, input)
        end
        return
      end

      # Gibberish never reaches the AI pipeline: filter first, no credits.
      if event.message? && Whatsapp::GarbageFilter.garbage?(event.text.to_s)
        Rails.logger.info "[WhatsappService] Gibberish message ignored from #{event.sender_id}"
        Whatsapp::ReplySender.send_to(
          event.sender_id,
          "No entendí 🤔 Escríbelo como gasto, ej: \"gasté 50 mil en mercado\"."
        )
        return
      end

      input = build_input(event)
      unless input
        # A re-sent interactive reply whose session already closed must not
        # die in silence: tell the user nothing is pending anymore.
        if event.message.type == "interactive"
          Rails.logger.info "[WhatsappService] Interactive reply without pending session from #{event.sender_id}"
          Whatsapp::ReplySender.send_to(
            event.sender_id,
            "Esta respuesta ya no aplica: no hay ninguna aclaración pendiente 🤔 " \
            "Escríbeme tus gastos como texto, ej: \"gasté 50 mil en mercado\"."
          )
          return
        end
        Rails.logger.info "[WhatsappService] Ignored unsupported message type #{event.message.type} " \
                          "from #{event.sender_id}"
        return
      end

      run_pipeline(user, event, input)
    end

    # Route a message to the user's pending clarification session:
    # interactive taps resolve deterministically, "cancelar" cancels, free
    # text goes to the LLM resolver (gibberish is filtered first — no credits
    # wasted). Returns [outcome, new_expense_fragment]; the fragment is
    # non-nil when the reply contained a new expense for the pipeline.
    def route_to_clarification(user, event, session)
      if event.message.type == "interactive" && event.interactive_reply
        outcome = Expenses::Clarification::Resolver.handle_tap(
          clarification: session, interactive_reply: event.interactive_reply
        )
        Rails.logger.info "[WhatsappService] Clarification tap for session #{session.id}: #{outcome}"
        return [ :handled, nil ]
      end

      reply_text = event.text.to_s
      if reply_text.match?(/\Acancela/i)
        session.close!(:cancelled)
        Whatsapp::ReplySender.send_to(
          session.phone_number,
          "Listo, cancelé la aclaración. Los gastos quedaron guardados para revisión manual en #{app_name}."
        )
        Rails.logger.info "[WhatsappService] Clarification cancelled for session #{session.id}"
        return [ :handled, nil ]
      end

      if Whatsapp::GarbageFilter.garbage?(reply_text)
        Rails.logger.info "[WhatsappService] Gibberish reply ignored for clarification #{session.id}"
        Whatsapp::ReplySender.send_to(
          session.phone_number,
          "No entendí 🤔 #{session.question}"
        )
        return [ :handled, nil ]
      end

      outcome, new_expense_text = Expenses::Clarification::Resolver.handle_reply(clarification: session,
                                                                                 reply_text: reply_text)
      Rails.logger.info "[WhatsappService] Clarification reply for session #{session.id}: #{outcome} " \
                        "(new_expense=#{new_expense_text.inspect})"
      if new_expense_text.present?
        [ :new_expense_fragment, new_expense_text ]
      else
        [ :handled, nil ]
      end
    end

    # Unconnected / disconnected numbers resolve to nil here: the historical
    # identity may exist but only an ACTIVE connection grants access.
    def resolve_user(sender_id)
      identity = WhatsappIdentity.find_by(phone_number: WhatsappIdentity.normalize(sender_id))
      identity&.active_connection&.user
    end

    # Channel dispatch: WhatsApp voice notes map to the audio channel, photos
    # to image (or text_image when the user adds a caption), typed text to the
    # text channel. Anything else (video, sticker, document) is not supported
    # yet.
    def build_input(event)
      message = event.message
      case message.type
      when "text"
        Expenses::Input.from_params("text", { text: event.text })
      when "audio"
        build_media_input(event, type: "audio")
      when "image"
        caption = message.caption
        build_media_input(event, type: caption ? "text_image" : "image", caption: caption)
      end
    end

    def build_media_input(event, type:, caption: nil)
      message = event.message
      media_id = message.file_id
      data_uri = Whatsapp::MediaFetcher.call(media_id: media_id, mime_type: message.mime_type)
      unless data_uri
        Whatsapp::ReplySender.send_to(
          event.sender_id,
          "No pude descargar el archivo, intenta de nuevo 👉"
        )
        return nil
      end

      filename = "whatsapp-#{message.file_id}.#{Expenses::Inputs::Audio.extension(data_uri, nil)}"
      params = { audio_data: data_uri, image_data: data_uri, text: caption, filename: filename }.compact
      Expenses::Input.from_params(type, params)
    end

    def run_pipeline(user, event, input)
      unless input.valid?
        Rails.logger.warn "[WhatsappService] Invalid #{event.message.type} input from #{event.sender_id}: " \
                          "#{input.errors.inspect}"
        return
      end

      Rails.logger.info "[WhatsappService] Pipeline starting for user=#{user.id} mid=#{event.mid} " \
                        "input_type=#{input.type}"
      begin
        result = Expenses::Processor.call(user: user, input: input, source: "whatsapp")
      rescue StandardError => e
        Rails.logger.error "[WhatsappService] Pipeline failed for message #{event.mid}: #{e.class}: #{e.message}"
        notify_failure(event.sender_id)
        return
      end

      candidates = result.candidates || []
      Rails.logger.info "[WhatsappService] Pipeline finished user=#{user.id} mid=#{event.mid} " \
                        "engine=#{result.engine.inspect} duration=#{result.duration_ms}ms " \
                        "candidates=#{candidates.size} errors=#{result.errors.inspect}"

      auto_confirm!(candidates)
      reply_summary(user, event, candidates)

      if candidates.any?
        Rails.logger.info "[WhatsappService] Created #{candidates.size} candidate(s) for " \
                          "user #{user.id} from message #{event.mid}"
      else
        Rails.logger.info "[WhatsappService] No candidates resolved for user #{user.id} " \
                          "from message #{event.mid} (errors=#{result.errors.inspect})"
      end
      candidates
    end

    # WhatsApp messages from a connected number are trusted input: candidates
    # the pipeline already resolved confidently (status "ready") are confirmed
    # into final Expenses immediately; anything uncertain stays for manual
    # review in the Expense Candidates panel.
    def auto_confirm!(candidates)
      ready = candidates.select(&:ready?)
      Rails.logger.info "[WhatsappService] Auto-confirming #{ready.size}/#{candidates.size} ready candidate(s)"
      ready.each(&:confirm!)
    end

    def reply_summary(user, event, candidates)
      return if candidates.empty?

      Rails.logger.info "[WhatsappService] Candidate summary for mid=#{event.mid}: " \
                        "statuses=#{candidates.map(&:status).tally.inspect}"

      lines = candidates.select(&:confirmed?).map do |candidate|
        "✅ Gasto registrado: #{format_candidate_amount(candidate)} – #{candidate.description.presence || 'sin descripción'}"
      end

      incomplete = candidates.select { |c| c.status == "needs_review" && c.missing_fields.present? }
      # Confirmations go FIRST (one batched message): the user sees what was
      # already created, and only THEN the clarification question — the
      # session's question is delivered by start_session! and lands last.
      if incomplete.any?
        Whatsapp::ReplySender.send_to(event.sender_id, lines.join("\n")) unless lines.empty?
        if (session = Expenses::Clarification::Resolver.start_session!(
          user: user, phone_number: event.sender_id, candidates: incomplete,
          original_message: event.text
        ))
          Rails.logger.info "[WhatsappService] Clarification session=#{session.id} started with " \
                            "#{incomplete.size} candidate(s) from mid=#{event.mid}"
          return
        end
      end

      candidates.select { |c| c.status == "needs_review" }.each do |candidate|
        what = candidate.description.presence || event.text.to_s.strip.presence || "tu gasto"
        lines << "🟡 Registré \"#{what}\" para revisión en #{app_name}#{missing_note(candidate)}."
      end
      return if lines.empty?

      Rails.logger.info "[WhatsappService] Sending summary reply (#{lines.size} line(s)) for mid=#{event.mid}"
      Whatsapp::ReplySender.send_to(event.sender_id, lines.join("\n"))
    rescue StandardError => e
      # The candidates may already be saved: never leave the user guessing
      # about what happened to their message.
      Rails.logger.error "[WhatsappService] Reply failed: #{e.class}: #{e.message}"
      notify_failure(event.sender_id)
    end

    def format_candidate_amount(candidate)
      ActionController::Base.helpers.number_to_currency(candidate.amount, unit: "$", delimiter: ".", separator: ",",
                                                        precision: 0)
    end

    # APP_NAME lets deployments rebrand the replies without code changes
    # (defaults to "Expense Tracker").
    def app_name
      ENV.fetch("APP_NAME", "Expense Tracker")
    end

    MISSING_FIELD_LABELS = {
      "amount" => "monto",
      "date" => "fecha",
      "description" => "descripción",
      "category_id" => "categoría",
      "money_source_id" => "fuente de dinero"
    }.freeze

    def missing_note(candidate)
      fields = Array(candidate.missing_fields).map { |field| MISSING_FIELD_LABELS.fetch(field, field) }
      " (faltan: #{fields.join(', ')})" if fields.present?
    end
  end
end
