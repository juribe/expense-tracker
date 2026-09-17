# frozen_string_literal: true

module Expenses
  module Inputs
    # Generic base64 data-URI parsing shared by the channels that carry binary
    # payloads (image, audio, file). Each typed input exposes its own
    # mime_type / extension / base64 / binary built on top of these, so its
    # validation and any consumer find the information from the typed input
    # class, not from the canonical Input.
    module DataUri
      module_function

      # Mime type from a data URI. An optional whitelist restricts the result
      # to supported formats (returns nil for anything else).
      def mime_type(uri, whitelist = nil)
        match = uri.to_s.match(/\Adata:([^;]+);base64,/)
        return nil unless match

        whitelist ? match[1].presence_in(whitelist) : match[1]
      end

      def base64(uri)
        uri.to_s.sub(/\Adata:[^;]+;base64,/, "")
      end

      def extension_from_filename(filename)
        ::File.extname(filename.to_s).delete(".").downcase.presence
      end
    end
  end
end
