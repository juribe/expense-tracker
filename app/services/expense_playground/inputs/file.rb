# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # File channel (PDF, CSV, Excel statements/uploads). The payload is a
    # base64 data URI; filename and password flow into metadata. The class owns
    # the general file-data methods (mime_type/extension/base64/binary) and its
    # validation rules.
    class File < Base
      extend Rules::File
      extend DataUri

      TYPE = "file"
      PAYLOAD_KEYS = %i[file_data].freeze
      META_KEYS = %i[filename password].freeze
      REQUIRED_FIELDS = { file_data: "file" }.freeze

      def self.mime_type(file_data)
        DataUri.mime_type(file_data)
      end

      def self.extension(file_data, filename)
        case mime_type(file_data)
        when "application/pdf" then "pdf"
        when "text/csv" then "csv"
        when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then "xlsx"
        when "application/vnd.ms-excel" then "xls"
        else
          DataUri.extension_from_filename(filename)
        end
      end

      def self.base64(file_data)
        DataUri.base64(file_data)
      end

      def self.binary(file_data)
        Base64.decode64(base64(file_data))
      rescue ArgumentError
        nil
      end

      def self.channel_errors(input)
        file_errors(input)
      end
    end
  end
end
