# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class AdaptersTest < ActiveSupport::TestCase
    test "builds a text input" do
      input = Adapters::Registry.build("text", { "text" => "50 mil" })
      assert input.valid?
      assert_equal "text", input.type
      assert_equal "50 mil", input.text
    end

    test "builds an image input" do
      input = Adapters::Registry.build("image", { "image_data" => "data:image/png;base64,Zm9v" })
      assert input.valid?
      assert_equal "image", input.type
      assert_equal "image/png", input.image_mime_type
    end

    test "builds a text + image input" do
      input = Adapters::Registry.build("text_image", {
        "text" => "recibo", "image_data" => "data:image/png;base64,Zm9v"
      })
      assert input.valid?
      assert_equal "text_image", input.type
      assert input.image?
    end

    test "unknown types produce an invalid input instead of raising" do
      input = Adapters::Registry.build("whatsapp", { "text" => "hola" })
      assert_not input.valid?
      assert input.errors.include?("Unknown input type.")
    end

    test "adapters receive symbolized params including metadata" do
      seen = nil
      adapter = Class.new(Adapters::Base) do
        define_method(:call) do |params|
          seen = params
          build_input(text: params[:text], metadata: params[:metadata])
        end
      end
      Adapters::Registry.register("custom_test", adapter)

      Adapters::Registry.build("custom_test", { "text" => "hola", "metadata" => { "chat_id" => 42 } })

      assert_equal "hola", seen[:text]
      assert_equal({ chat_id: 42 }, seen[:metadata])
    ensure
      Adapters::Registry.adapters.delete("custom_test")
    end

    test "registered types list includes the built-in channels" do
      assert_includes Adapters::Registry.types, "text"
      assert_includes Adapters::Registry.types, "image"
      assert_includes Adapters::Registry.types, "text_image"
    end
  end
end
