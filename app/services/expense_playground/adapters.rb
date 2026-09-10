# frozen_string_literal: true

module ExpensePlayground
  # Input adapters decouple ingestion channels from the processing pipeline.
  # Each adapter turns channel-specific params into the canonical
  # ExpensePlayground::Input; the pipeline never knows where the data came from.
  module Adapters
    # Contract for every adapter:
    #
    #   class WhatsAppAdapter < ExpensePlayground::Adapters::Base
    #     TYPE = "whatsapp"
    #
    #     def call(params)
    #       message = fetch_message(params[:message_id]) # channel-specific
    #       build_input(
    #         text: message.body,
    #         image_data: message.attachment_data_uri,
    #         metadata: { chat_id: message.chat_id, sender: message.sender }
    #       )
    #     end
    #   end
    #
    #   ExpensePlayground::Adapters.register("whatsapp", WhatsAppAdapter)
    #
    # Voice adapters pass the transcript in `text`; email/PDF adapters inline
    # extracted content the same way — the pipeline stays untouched.
    class Base
      TYPE = nil

      def call(_params)
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      private

      def build_input(text: nil, image_data: nil, audio_data: nil, metadata: {})
        Input.new(type: self.class::TYPE, text: text, image_data: image_data, audio_data: audio_data, metadata: metadata)
      end
    end

    class TextAdapter < Base
      TYPE = "text"

      def call(params)
        build_input(text: params[:text], metadata: params[:metadata] || {})
      end
    end

    class ImageAdapter < Base
      TYPE = "image"

      def call(params)
        build_input(image_data: params[:image_data], metadata: params[:metadata] || {})
      end
    end

    class TextImageAdapter < Base
      TYPE = "text_image"

      def call(params)
        build_input(text: params[:text], image_data: params[:image_data], metadata: params[:metadata] || {})
      end
    end

    # Audio notes become text through SpeechToText before reaching the
    # pipeline, so this adapter only carries the payload + its label.
    class AudioAdapter < Base
      TYPE = "audio"

      def call(params)
        metadata = (params[:metadata] || {}).merge(filename: params[:filename].to_s)
        build_input(text: params[:text], audio_data: params[:audio_data], metadata: metadata)
      end
    end

    # File adapter for PDF, CSV, and Excel uploads. The file payload is a
    # base64 data URI (consistent with image/audio handling). The pipeline
    # extracts text and runs AI extraction on it.
    class FileAdapter < Base
      TYPE = "file"

      def call(params)
        metadata = (params[:metadata] || {}).merge(filename: params[:filename].to_s, password: params[:password].to_s)
        build_input(file_data: params[:file_data], metadata: metadata)
      end
    end

    # Maps an input type to its adapter. Unknown types produce an Input with a
    # nil type, which fails Input validation with "Unknown input type".
    module Registry
      @adapters = {}

      class << self
        attr_reader :adapters

        def register(type, adapter_class)
          @adapters[type.to_s] = adapter_class
        end

        def types
          @adapters.keys
        end

        # Factory used by the controller. `params` is a raw channel params
        # object (Hash or ActionController::Parameters); the adapter decides
        # what it needs from it.
        def build(type, params)
          adapter_class = @adapters[type.to_s]
          return Input.new(type: type.to_s, metadata: {}) unless adapter_class

          adapter_class.new.call(symbolize(params))
        end

        private

        def symbolize(params)
          hash = params.is_a?(Hash) ? params : (params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h)
          hash.deep_symbolize_keys
        end
      end
    end
  end
end

ExpensePlayground::Adapters::Registry.register("text", ExpensePlayground::Adapters::TextAdapter)
ExpensePlayground::Adapters::Registry.register("image", ExpensePlayground::Adapters::ImageAdapter)
ExpensePlayground::Adapters::Registry.register("text_image", ExpensePlayground::Adapters::TextImageAdapter)
ExpensePlayground::Adapters::Registry.register("audio", ExpensePlayground::Adapters::AudioAdapter)
ExpensePlayground::Adapters::Registry.register("file", ExpensePlayground::Adapters::FileAdapter)
