# frozen_string_literal: true

module Expenses
  # Typed ingestion inputs. One class per channel shape (text, image,
  # text+image, audio, file); each declares which params it accepts, which
  # fields it requires and how to validate them, and converts channel params
  # into the canonical Expenses::Input via +to_input+.
  #
  # Typed inputs are reusable across transports: the same Image input serves
  # the playground UI and a future WhatsApp/email sender, because
  # +to_input+ only cares about the normalized params it is given.
  module Inputs
    # Maps a type string to its typed input class. Unknown types return nil
    # and the factory then produces an invalid Input ("Unknown input type.").
    def self.for_type(type)
      TYPES[type.to_s]
    end

    def self.types
      TYPES.keys
    end

    TYPES = {
      "text" => Text,
      "image" => Image,
      "text_image" => TextImage,
      "audio" => Audio,
      "file" => File
    }.freeze
  end
end
