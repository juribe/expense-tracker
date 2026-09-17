# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    module Rules
      # File payload rules. Extended by the file typed input; the general
      # file-data methods (extension/base64/binary/mime_type) live on the typed
      # input class and are reached through the extended singleton.
      module File
        SUPPORTED_EXTENSIONS = %w[pdf csv xlsx xls].freeze
        FILE_MAX_BYTES = 20.megabytes

        def file_errors(input)
          errors = []
          ext = extension(input.file_data, input.filename)
          if ext.blank? || !ext.in?(SUPPORTED_EXTENSIONS)
            errors << "Unsupported file format. Use PDF, CSV, or Excel."
          elsif decoded_file_size(input) > FILE_MAX_BYTES
            errors << "File is too large (max #{FILE_MAX_BYTES / 1.megabyte} MB)."
          end
          errors
        end

        private

        def decoded_file_size(input)
          Base64.decode64(base64(input.file_data)).bytesize
        rescue ArgumentError
          FILE_MAX_BYTES + 1
        end
      end
    end
  end
end
