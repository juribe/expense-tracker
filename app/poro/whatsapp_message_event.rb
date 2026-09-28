# frozen_string_literal: true

class WhatsappMessageEvent
  attr_reader :metadata, :contact, :message

  def initialize(metadata:, contact:, message:)
    @metadata = metadata
    @contact = contact
    @message = message
  end

  def sender_id
    message.from
  end

  def chat_id
    message.chat_id
  end

  def recipient_id
    metadata["phone_number_id"]
  end

  def mid
    message.id
  end

  def text
    message.text_body
  end

  # Tapped option of an interactive list/button message:
  # { "id" => "source:23", "title" => "Davibank" } or nil.
  def interactive_reply
    message.interactive_reply
  end

  def caption
    message.caption
  end

  def file_name
    message.file_name
  end

  def mime_type
    message.mime_type
  end

  def file_id
    message.file_id
  end

  def body
    message.body
  end

  def timestamp
    return unless message.timestamp
    Time.at(message.timestamp.to_i)
  end

  def sender_name
    contact.name
  end

  def message?
    message.type == "text"
  end

  def attachment?
    message.attachment?
  end

  def raw
    message.raw
  end
end
