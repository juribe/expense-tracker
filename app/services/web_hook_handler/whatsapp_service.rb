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

      payload.message_events.each do |event|
        if connect_command?(event)
          Whatsapp::ConnectService.call(event: event)
        else
          process_message(event)
        end
      end
    rescue JSON::ParserError => e
      Rails.logger.error "[WhatsappService] Invalid payload: #{e.message}"
    end

    private

    def connect_command?(event)
      event.message? && event.text.to_s.match?(/\A\s*CONNECT\s+\S+/i)
    end

    def process_message(event)
      user = resolve_user(event.sender_id)

      unless user
        Rails.logger.info "[WhatsappService] Unconnected number #{event.sender_id}; sending connect instructions"
        Whatsapp::ReplySender.send_to(
          event.sender_id,
          "Hola 👋 Conecta tu WhatsApp desde Configuración → WhatsApp del Expense Tracker para registrar gastos por este chat."
        )
        return
      end

      input = build_input(event)
      unless input
        Rails.logger.info "[WhatsappService] Ignored unsupported message type #{event.message.type} " \
                          "from #{event.sender_id}"
        return
      end

      run_pipeline(user, event, input)
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

      result = Expenses::Processor.call(user: user, input: input, source: "whatsapp")
      candidates = result.candidates || []

      auto_confirm!(candidates)
      reply_summary(event, candidates)

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
      candidates.select(&:ready?).each(&:confirm!)
    end

    def reply_summary(event, candidates)
      return if candidates.empty?

      lines = candidates.select(&:confirmed?).map do |candidate|
        "✅ Gasto registrado: #{format_candidate_amount(candidate)} – #{candidate.description.presence || 'sin descripción'}"
      end
      lines += candidates.select { |c| c.status == "needs_review" }.map do |candidate|
        what = candidate.description.presence || event.text.to_s.strip.presence || "tu gasto"
        "🟡 Registré \"#{what}\" para revisión en #{app_name}#{missing_note(candidate)}."
      end
      return if lines.empty?

      Whatsapp::ReplySender.send_to(event.sender_id, lines.join("\n"))
    rescue StandardError => e
      Rails.logger.error "[WhatsappService] Reply failed: #{e.message}"
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
