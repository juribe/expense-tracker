# frozen_string_literal: true

module ExpensePlayground
  module Inputs
    # File channel (PDF, CSV, Excel statements/uploads). The payload is a
    # base64 data URI; filename and password flow into metadata. Format/size
    # rules come from Rules::File.
    class File < Base
      extend Rules::File

      TYPE = "file"
      PAYLOAD_KEYS = %i[file_data].freeze
      META_KEYS = %i[filename password].freeze
      REQUIRED_FIELDS = { file_data: "file" }.freeze

      def self.channel_errors(input)
        file_errors(input)
      end
    end
  end
end
