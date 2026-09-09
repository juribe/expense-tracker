# frozen_string_literal: true

require "test_helper"

module Ocr
  # Local OCR must never upload anything: it reads with Tesseract and
  # returns plain text (or nil when nothing is readable). Live tests are
  # skipped when Tesseract is not installed.
  class LocalReaderTest < ActiveSupport::TestCase
    FIXTURE = Rails.root.join("test/fixtures/files/receipt_fixture.png")

    test "decodes data URIs and raw base64 payloads" do
      reader = LocalReader.new(image_data: "data:image/png;base64,#{Base64.strict_encode64("PNGDATA")}")
      assert_equal "PNGDATA", reader.send(:decoded)

      reader = LocalReader.new(image_data: Base64.strict_encode64("RAWBYTES"))
      assert_equal "RAWBYTES", reader.send(:decoded)

      reader = LocalReader.new(image_data: "data:image/png;base64,!!!!not-base64!!!!")
      assert_equal "", reader.send(:decoded)
    end

    test "maps mime types to file extensions" do
      {
        "data:image/jpeg;base64,x" => ".jpg",
        "data:image/png;base64,x" => ".png",
        "data:image/webp;base64,x" => ".webp",
        "data:image/gif;base64,x" => ".gif",
        "data:image/tiff;base64,x" => ".tiff",
        "unknown" => ".png"
      }.each do |payload, expected|
        assert_equal expected, LocalReader.new(image_data: payload).send(:extension), payload
      end
    end

    test "returns nil for an empty payload without invoking tesseract" do
      assert_nil LocalReader.call(image_data: "")
      assert_nil LocalReader.call(image_data: "!!!not-base64!!!")
    end

    test "reads text from the fixture receipt when tesseract is available" do
      skip "tesseract is not installed" unless LocalReader.available?

      text = LocalReader.call(image_data: "data:image/png;base64,#{Base64.strict_encode64(File.binread(FIXTURE))}")

      assert text.present?
      assert_match(/TOTAL/i, text)
      assert_match(/NEQUI/i, text)
    end

    test "returns nil for an image with no text when tesseract is available" do
      skip "tesseract is not installed" unless LocalReader.available?

      one_pixel_png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

      assert_nil LocalReader.call(image_data: "data:image/png;base64,#{one_pixel_png}")
    end
  end
end
