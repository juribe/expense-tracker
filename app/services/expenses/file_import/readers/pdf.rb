# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      # PDF reader. Extracts page text; encrypted documents surface a
      # password prompt through the pipeline when none was supplied, and an
      # incorrect-password error when one was supplied and still fails.
      class Pdf < Base
        MAX_PAGES = 15
        MAX_TEXT_BYTES = 2.megabytes

        def call
          with_tempfile("pdf") do |tmp|
            reader = if password.present?
              PDF::Reader.new(tmp, password: password)
            else
              PDF::Reader.new(tmp)
            end

            text = +""
            [ reader.page_count, MAX_PAGES ].min.times do |index|
              text << reader.page(index + 1).text.to_s << "\n\n"
              break if text.bytesize >= MAX_TEXT_BYTES
            end

            Extraction.new(text: text[0, MAX_TEXT_BYTES].presence, rows: [], headers: [])
          end
        rescue PDF::Reader::EncryptedPDFError
          # The caller presents the password prompt when none was supplied; when
          # one was supplied and the document is still locked, that is an
          # incorrect-password error. Both errors are surfaced to the user.
          errors << if password.present?
            I18n.t("wizard.upload.password_error")
          else
            I18n.t("wizard.upload.pdf_encrypted")
          end
          Extraction.empty
        rescue PDF::Reader::Error
          errors << I18n.t("wizard.upload.pdf_unreadable")
          Extraction.empty
        end
      end
    end
  end
end
