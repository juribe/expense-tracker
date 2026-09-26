# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      # Shared reader state: the raw file bytes plus the pipeline error and
      # warning sinks a reader appends to (password errors, unreadable PDFs).
      # Each concrete reader turns the bytes into an Extraction and owns the
      # quirks of its format; the pipeline only picks the reader by extension.
      class Base
        def self.call(binary:, errors:, warnings:, password: nil)
          new(binary: binary, errors: errors, warnings: warnings, password: password).call
        end

        def initialize(binary:, errors:, warnings:, password: nil)
          @binary = binary
          @errors = errors
          @warnings = warnings
          @password = password.to_s.presence
        end

        def call
          raise NotImplementedError
        end

        private

        attr_reader :binary, :errors, :warnings, :password

        # Uploaded binaries are raw byte strings. Modern bank exports are UTF-8;
        # legacy latin-1 ones would make every accented character invalid in a
        # UTF-8 view, so fall back to Windows-1252 when the bytes are not valid
        # UTF-8. Never call String#encode straight from ASCII-8BIT: it treats
        # multi-byte UTF-8 sequences as invalid and silently strips accents.
        def decode_to_utf8(raw)
          utf8 = raw.dup.force_encoding(Encoding::UTF_8)
          return utf8.scrub("") if utf8.valid_encoding?

          raw.dup.force_encoding(Encoding::WINDOWS_1252)
             .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end

        # Some format libraries require a file on disk; the temp file lives
        # exactly for the duration of the block.
        def with_tempfile(extension)
          require "tempfile"
          tmp = Tempfile.new([ "upload", ".#{extension}" ])
          tmp.binmode
          tmp.write(binary)
          tmp.rewind
          yield tmp
        ensure
          tmp&.close!
        end
      end
    end
  end
end
