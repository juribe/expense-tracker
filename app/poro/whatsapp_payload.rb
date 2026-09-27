# frozen_string_literal: true
class WhatsappPayload
  attr_reader :object, :entries

  def initialize(payload)
    data = payload.is_a?(String) ? JSON.parse(payload) : payload
    @object = data["object"]
    @entries = Array(data["entry"]).map { |entry| Entry.new(entry) }
  end

  # Collect all message events from all entries
  def message_events
    entries.flat_map(&:message_events)
  end

  # ================================================================
  # Inner Classes
  # ================================================================

  class Entry
    attr_reader :id, :changes

    def initialize(data)
      @id = data["id"]
      @changes = Array(data["changes"]).map { |change| Change.new(change) }
    end

    def message_events
      changes.flat_map(&:message_events)
    end
  end

  class Change
    attr_reader :field, :value

    def initialize(data)
      @field = data["field"]
      @value = Value.new(data["value"]) if data["value"]
    end

    def message_events
      return [] unless field == "messages"
      value.message_events
    end
  end

  class Value
    attr_reader :messaging_product, :metadata, :contacts, :messages

    def initialize(data)
      @messaging_product = data["messaging_product"]
      @metadata = data["metadata"]
      @contacts = Array(data["contacts"]).map { |c| Contact.new(c) }
      @messages = Array(data["messages"]).map { |m| Message.new(m) }
    end

    def message_events
      messages.map do |message|
        WhatsappMessageEvent.new(
          metadata: metadata,
          contact: contacts.first,
          message: message
        )
      end
    end
  end

  class Contact
    attr_reader :wa_id, :profile

    def initialize(data)
      @wa_id = data["wa_id"]
      @profile = data["profile"] || {}
    end

    def name
      profile["name"]
    end
  end

  class Message
    attr_reader :id, :from, :timestamp, :type, :text, :document, :image, :audio, :video, :raw, :sticker

    def initialize(data)
      @raw = data
      @id = data["id"]
      @from = data["from"]
      @timestamp = data["timestamp"]
      @type = data["type"]
      @text = data["text"]
      @document = data["document"]
      @image = data["image"]
      @audio = data["audio"]
      @video = data["video"]
      @sticker = data["sticker"]
    end

    def text_body
      text&.dig("body")
    end

    # ============ Document / Media Helpers ============

    def attachment?
      %w[document image audio video sticker].include?(type)
    end

    def caption
      media_data&.dig("caption")
    end

    def file_name
      media_data&.dig("filename")
    end

    def mime_type
      media_data&.dig("mime_type")
    end

    def file_id
      media_data&.dig("id")
    end

    def sha256
      media_data&.dig("sha256")
    end

    private

    def media_data
      case type
      when "document" then document
      when "image"    then image
      when "audio"    then audio
      when "video"    then video
      when "sticker"  then sticker
      end
    end
  end
end
