# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class InputsTest < ActiveSupport::TestCase
    # A channel-specific subclass reusing the canonical image type. This is the
    # reuse pattern: a WhatsApp sender could subclass Inputs::Image (inheriting
    # its validation rules) and only add its own metadata keys.
    class WhatsAppImage < Inputs::Image
      TYPE = "image"
      META_KEYS = %i[chat_id sender].freeze
    end

    test "text to_input produces a canonical text input" do
      input = Inputs::Text.to_input({ "text" => "50 mil" })
      assert_instance_of Input, input
      assert_equal "text", input.type
      assert_equal "50 mil", input.text
    end

    test "image to_input is reusable for any transport (e.g. WhatsApp)" do
      input = Inputs::Image.to_input({
        "image_data" => "data:image/jpeg;base64,Zm9v",
        "metadata" => { "chat_id" => 12, "sender" => "Maria" }
      })
      assert input.valid?
      assert_equal "image", input.type
      assert_equal "image/jpeg", input.image_mime_type
      assert_equal({ chat_id: 12, sender: "Maria" }, input.metadata)
    end

    test "text_image to_input requires both text and image to be valid" do
      input = Inputs::TextImage.to_input({ "text" => "recibo", "image_data" => "data:image/png;base64,Zm9v" })
      assert input.valid?

      missing = Inputs::TextImage.to_input({ "text" => "recibo" })
      assert_not missing.valid?
      assert_includes missing.errors, "No image was provided."
    end

    test "audio to_input carries its filename in metadata and validates the format" do
      good = Inputs::Audio.to_input({ "audio_data" => "data:audio/ogg;base64,b3B1cw==", "filename" => "note.ogg" })
      assert good.valid?
      assert_equal "note.ogg", good.filename

      bad = Inputs::Audio.to_input({ "audio_data" => "data:audio/x-flac;base64,ZmxsYWM=" })
      assert_not bad.valid?
      assert_includes bad.errors, "Unsupported audio format. Use OGG, OPUS, M4A, MP3, WAV or WEBM."
    end

    test "file to_input carries filename and password in metadata" do
      input = Inputs::File.to_input({
        "file_data" => "data:application/pdf;base64,Zm9v", "filename" => "stmt.pdf", "password" => "secret"
      })
      assert input.valid?
      assert_equal "secret", input.metadata[:password]
    end

    test "each typed input declares its own required fields" do
      assert_equal({ text: "text" }, Inputs::Text.required_fields)
      assert_equal({ image_data: "image" }, Inputs::Image.required_fields)
      assert_equal({ text: "text", image_data: "image" }, Inputs::TextImage.required_fields)
      assert_equal({ audio_data: "audio" }, Inputs::Audio.required_fields)
      assert_equal({ file_data: "file" }, Inputs::File.required_fields)
    end

    test "valid? reports missing required fields per typed input" do
      assert_not Inputs::Text.valid?({})
      assert Inputs::Text.valid?({ text: "hola" })
      assert_not Inputs::File.valid?({ filename: "stmt.pdf" })
      assert Inputs::File.valid?({ file_data: "data:application/pdf;base64,Zm9v" })
    end

    test "image typed input owns format rules (rejects unsupported formats)" do
      input = Inputs::Image.to_input({ "image_data" => "data:image/bmp;base64,Zm9v" })
      assert_not input.valid?
      assert_includes input.errors, "Unsupported image format. Use JPEG, PNG, WebP or GIF."
    end

    test "file typed input owns format rules (rejects unknown extensions)" do
      input = Inputs::File.to_input({ "file_data" => "data:text/plain;base64,cGxhaW4=", "filename" => "notes.txt" })
      assert_not input.valid?
      assert_includes input.errors, "Unsupported file format. Use PDF, CSV, or Excel."
    end

    test "channel subclasses inherit the canonical type's validation rules" do
      assert_not WhatsAppImage.valid?({ "image_data" => "data:image/bmp;base64,Zm9v" })
      assert_equal({ image_data: "image" }, WhatsAppImage.required_fields)
    end

    test "the canonical Input delegates validity to the typed input" do
      input = Input.from_params("image", { "image_data" => "data:image/bmp;base64,Zm9v" })
      assert_not input.valid?
      assert_includes input.errors, "Unsupported image format. Use JPEG, PNG, WebP or GIF."
    end

    test "the factory dispatches to typed inputs and rejects unknown types" do
      assert_instance_of Input, Input.from_params("image", { image_data: "data:image/png;base64,Zm9v" })
      assert_nil Inputs.for_type("whatsapp")
    end

    test "channel inputs can subclass a canonical type and stay valid (e.g. WhatsApp image)" do
      params = { image_data: "data:image/jpeg;base64,Zm9v", chat_id: 12, sender: "Maria" }
      assert WhatsAppImage.valid?(params)
      assert_not WhatsAppImage.valid?(params.except(:image_data))

      input = WhatsAppImage.to_input(params)
      assert input.valid?
      assert_equal "image", input.type
      assert_equal({ chat_id: 12, sender: "Maria" }, input.metadata)
    end
  end
end
