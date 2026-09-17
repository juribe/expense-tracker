# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class InputTest < ActiveSupport::TestCase
    test "from_params builds a text input" do
      input = Input.from_params("text", { "text" => "50 mil" })
      assert input.valid?
      assert_equal "text", input.type
      assert_equal "50 mil", input.text
    end

    test "from_params builds an image input" do
      input = Input.from_params("image", { "image_data" => "data:image/png;base64,Zm9v" })
      assert input.valid?
      assert_equal "image", input.type
      assert_equal "image/png", input.image_mime_type
    end

    test "from_params builds a text + image input" do
      input = Input.from_params("text_image", {
        "text" => "recibo", "image_data" => "data:image/png;base64,Zm9v"
      })
      assert input.valid?
      assert_equal "text_image", input.type
      assert input.image?
    end

    test "from_params builds an audio input with its filename in metadata" do
      input = Input.from_params("audio", {
        "text" => "cine", "audio_data" => "data:audio/ogg;base64,b3B1cw==", "filename" => "note.ogg"
      })
      assert input.valid?
      assert_equal "audio", input.type
      assert input.audio?
      assert_equal "note.ogg", input.filename
    end

    test "from_params builds a file input with filename and password in metadata" do
      input = Input.from_params("file", {
        "file_data" => "data:application/pdf;base64,Zm9v", "filename" => "stmt.pdf", "password" => "secret"
      })
      assert input.valid?
      assert_equal "file", input.type
      assert input.file?
      assert_equal "pdf", input.file_extension
      assert_equal "secret", input.metadata[:password]
    end

    test "unknown types produce an invalid input instead of raising" do
      input = Input.from_params("whatsapp", { "text" => "hola" })
      assert_not input.valid?
      assert input.errors.include?("Unknown input type.")
    end

    test "from_params symbolizes string keys and deep symbolizes metadata" do
      input = Input.from_params("text", {
        "text" => "hola", "metadata" => { "chat_id" => 42 }
      })
      assert_equal "hola", input.text
      assert_equal({ chat_id: 42 }, input.metadata)
    end

    test "permitted key map covers every built-in input type" do
      Input::PERMITTED_KEYS.each_key do |type|
        assert_includes Input::TYPES, type
      end
    end
  end
end