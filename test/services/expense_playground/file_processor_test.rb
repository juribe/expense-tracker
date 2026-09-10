# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class FileProcessorTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "File Processor User", email: "file-processor@example.com", password: "password123")
    end

    # Minimal but structurally valid PDF whose /Encrypt entry makes pdf-reader
    # treat the document as password protected from the start.
    def encrypted_pdf_data_uri
      objs = {}
      objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
      objs[2] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
      objs[3] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"
      objs[4] = "<< /Length 55 >>\nstream\nBT /F1 24 Tf 100 700 Td (DIDI FOOD 45000) Tj ET\nendstream"
      objs[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      objs[6] = "<< /Filter /Standard /V 1 /R 2 /O <00000000000000000000000000000000> /U <00000000000000000000000000000000> /P -44 >>"

      out = +"%PDF-1.4\n"
      offsets = { 0 => 0 }
      (1..6).each do |i|
        offsets[i] = out.length
        out << "#{i} 0 obj\n#{objs[i]}\nendobj\n"
      end
      xref_pos = out.length
      out << "xref\n0 #{offsets.size}\n"
      offsets.each_value { |off| out << format("%010d 00000 n \n", off) }
      out << "trailer\n<< /Size #{offsets.size} /Root 1 0 R /Encrypt 6 0 R >>\nstartxref\n#{xref_pos}\n%%EOF\n"

      "data:application/pdf;base64,#{Base64.strict_encode64(out)}"
    end

    test "reports that a PDF without a password is password protected" do
      result = FileProcessor.call(user: @user, file_data: encrypted_pdf_data_uri, filename: "stmt.pdf")

      assert_not result.ok?
      assert result.errors.any? { |message| message =~ /password|contrase[ñn]a/i }
    end

    test "reports an incorrect password when a password was supplied and the PDF still does not open" do
      result = FileProcessor.call(user: @user, file_data: encrypted_pdf_data_uri, filename: "stmt.pdf", password: "wrong")

      assert_not result.ok?
      assert result.errors.any? { |message| message =~ /incorrect|incorrecta/i }
    end

    test "does not persist or leak the supplied PDF password" do
      result = FileProcessor.call(user: @user, file_data: encrypted_pdf_data_uri,
                                  filename: "stmt.pdf", password: "supersecret")

      assert_not result.ok?
      all_text = [ result.errors, result.warnings, result.candidates.map(&:to_h) ].flatten.compact.join(" ")
      assert_not_includes all_text, "supersecret"
    end

    test "extracts transactions from a CSV deterministically" do
      csv = "Fecha,Descripcion,Valor\n2026-09-09,DIDI FOOD,45000\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      result = FileProcessor.call(user: @user, file_data: file_data, filename: "stmt.csv")

      assert result.ok?
      assert_equal 1, result.candidates.length
      assert_equal "DIDI FOOD", result.candidates.first.description
      assert_equal BigDecimal("45000"), result.candidates.first.amount
    end

    test "rejects an unsupported file extension" do
      result = FileProcessor.call(user: @user, file_data: "data:text/plain;base64,cGxhaW4=", filename: "notes.txt")

      assert_not result.ok?
    end
  end
end
