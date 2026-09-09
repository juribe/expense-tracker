# frozen_string_literal: true

require "base64"
require "open3"
require "tempfile"
require "timeout"

module Ocr
  # Reads the visible text of an image LOCALLY with Tesseract, so receipts
  # never leave the machine. This is the first OCR pass for image inputs;
  # the vision AI model is only a fallback for images Tesseract cannot read.
  #
  # The app runs in a Linux container, where Tesseract is installed via the
  # Dockerfile (tesseract-ocr + tesseract-ocr-spa).
  #
  #   Ocr::LocalReader.call(image_data: "data:image/jpeg;base64,...")
  #     => "SUPERMERCADO ÉXITO\nTOTAL 87.500..." | nil
  #
  # Returns nil when Tesseract is not installed, fails, or reads no text —
  # the caller is expected to fall back to the next OCR strategy.
  class LocalReader
    # Full path override for non-PATH installs (e.g. MacPorts: /opt/local/bin/tesseract).
    TESSERACT_BIN = ENV.fetch("TESSERACT_BIN", "tesseract").freeze
    LANGUAGES = ENV.fetch("TESSERACT_LANGUAGES", "spa+eng").freeze
    ENGINE_TIMEOUT_SECONDS = 45
    DATA_URI_PATTERN = /\Adata:image\/(?<type>[a-z0-9.+-]+);base64,(?<payload>.+)\z/m.freeze

    def self.call(image_data:)
      new(image_data: image_data).call
    end

    def initialize(image_data:)
      @image_data = image_data.to_s
    end

    def call
      return nil unless available?
      return nil if decoded.blank?

      Tempfile.create([ "expense_ocr", extension ]) do |file|
        file.binmode
        file.write(decoded)
        file.flush
        read_text(file.path)
      end
    end

    def available?
      self.class.available?
    end

    def self.available?
      system(TESSERACT_BIN, "--version", out: File::NULL, err: File::NULL) ? true : false
    end

    private

    def read_text(path)
      Timeout.timeout(ENGINE_TIMEOUT_SECONDS) do
        stdout, _stderr, _status = Open3.capture3(TESSERACT_BIN, path, "stdout", "-l", LANGUAGES)
        stdout.to_s.strip.presence
      end
    rescue StandardError => e
      Rails.logger.warn("[ocr] tesseract failed: #{e.class}: #{e.message}")
      nil
    end

    def decoded
      match = DATA_URI_PATTERN.match(@image_data)
      payload = match ? match[:payload] : @image_data
      Base64.strict_decode64(payload)
    rescue ArgumentError
      ""
    end

    def extension
      mime = DATA_URI_PATTERN.match(@image_data)&.[](:type)
      case mime
      when "jpeg" then ".jpg"
      when "png", "webp", "gif", "tiff" then ".#{mime}"
      else ".png"
      end
    end
  end
end
