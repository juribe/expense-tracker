# frozen_string_literal: true

module Expenses
  module FileImport
    module Readers
      # PDF reader. Extracts page text; encrypted documents surface a
      # password prompt through the pipeline when none was supplied, and an
      # incorrect-password error when one was supplied and still fails.
      class Pdf < Base
        def call
          with_tempfile("pdf") do |tmp|
            reader = if password.present?
              PDF::Reader.new(tmp, password: password)
            else
              PDF::Reader.new(tmp)
            end

            text = reader.pages.map(&:text).join("\n\n").presence
            Extraction.new(text: text, rows: [], headers: [])
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
