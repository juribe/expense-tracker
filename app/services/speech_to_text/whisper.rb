# frozen_string_literal: true

require "base64"
require "open3"
require "tempfile"
require "timeout"

module SpeechToText
  # LOCAL speech-to-text provider backed by faster-whisper (Python). Nothing
  # leaves the machine: audio is preprocessed with FFmpeg into a normalized
  # 16 kHz mono WAV and then transcribed by a short-lived Python process.
  #
  #   SpeechToText::Whisper.call(audio_data: "data:audio/ogg;base64,...", filename: "note.ogg")
  #     => #<SpeechToText::Result text: "Este es un ejemplo.", language: "es", ...>
  #
  # Rails knows nothing about faster-whisper, Python, FFmpeg, or model files
  # beyond this class: it depends on SpeechToText, not on this provider.
  class Whisper
    PROVIDER_NAME = "whisper"
    DEFAULT_MODEL = "small"
    DEFAULT_DEVICE = "cpu"
    DEFAULT_COMPUTE_TYPE = "int8"
    DEFAULT_BEAM_SIZE = 5
    DEFAULT_TIMEOUT_SECONDS = 300
    SCRIPT_PATH = Rails.root.join("script/whisper_transcribe.py")
    PYTHON_BIN_FALLBACKS = [ "whisper-env/bin/python", "python3", "python" ].freeze

    # Supported input containers. The input does NOT have to be WAV or 16 kHz
    # — AudioPreprocessor normalizes whatever comes in.
    SUPPORTED_EXTENSIONS = {
      "ogg" => ".ogg", "opus" => ".ogg", "m4a" => ".m4a", "mp3" => ".mp3",
      "wav" => ".wav", "webm" => ".webm"
    }.freeze
    MIME_EXTENSIONS = {
      "audio/ogg" => "ogg", "application/ogg" => "ogg", "audio/opus" => "opus",
      "audio/mp4" => "m4a", "audio/x-m4a" => "m4a", "audio/mpeg" => "mp3",
      "audio/mp3" => "mp3", "audio/wav" => "wav", "audio/x-wav" => "wav",
      "audio/wave" => "wav", "audio/webm" => "webm"
    }.freeze
    DATA_URI_PATTERN = /\Adata:audio\/[a-z0-9.+-]+(?:;[^;,]+)*;base64,(?<payload>.+)\z/m.freeze

    class << self
      def call(audio_data:, filename: nil)
        new(audio_data: audio_data, filename: filename).transcribe
      end

      def name
        PROVIDER_NAME
      end
    end

    def initialize(audio_data:, filename: nil)
      @audio_data = audio_data.to_s
      @filename = filename.to_s
    end

    def transcribe
      input_file = nil
      preprocessed = nil

      input_file = write_input_tempfile
      preprocessed = AudioPreprocessor.call(audio_path: input_file.path)
      raw = execute(preprocessed.path)
      build_result(raw)
    ensure
      cleanup(preprocessed)
      cleanup(input_file)
    end

    private

    # Tempfile.create returns a plain File on this Ruby, and File#unlink was
    # removed in recent versions — delete by path so both variants work.
    def cleanup(file)
      return if file.nil?

      file.close unless file.closed?
      File.delete(file.path) if File.exist?(file.path)
    rescue StandardError => e
      Rails.logger.warn("[speech_to_text] temp file cleanup failed: #{e.class}: #{e.message}")
    end

    # ------------------------------------------------------------------ result

    def build_result(raw)
      Result.new(
        text: raw[:text].to_s,
        language: raw[:language].presence,
        language_probability: raw[:language_probability],
        duration: raw[:duration],
        provider: PROVIDER_NAME,
        model: model,
        metadata: {
          device: device,
          compute_type: compute_type,
          beam_size: DEFAULT_BEAM_SIZE,
          configured_language: language
        }
      )
    end

    # ----------------------------------------------------------------- config

    def model
      ENV.fetch("WHISPER_MODEL", DEFAULT_MODEL)
    end

    def device
      ENV.fetch("WHISPER_DEVICE", DEFAULT_DEVICE)
    end

    def compute_type
      ENV.fetch("WHISPER_COMPUTE_TYPE", DEFAULT_COMPUTE_TYPE)
    end

    # nil means "let faster-whisper detect the language automatically".
    def language
      ENV["WHISPER_LANGUAGE"].presence
    end

    def timeout_seconds
      ENV.fetch("WHISPER_TIMEOUT", DEFAULT_TIMEOUT_SECONDS).to_i
    end

    def python_bin
      explicit = ENV["WHISPER_PYTHON"].presence
      return explicit if explicit

      PYTHON_BIN_FALLBACKS.each do |candidate|
        expanded = Rails.root.join(candidate).to_s
        return expanded if File.executable?(expanded)
      end
      "python3"
    end

    # ------------------------------------------------------------ execution

    # Runs the Python process and returns the parsed transcript payload.
    # Raises SpeechToText::TranscriptionError with an application-level
    # message; raw Python stack traces are logged, never surfaced.
    def execute(audio_path)
      Timeout.timeout(timeout_seconds) do
        stdout, stderr, status = Open3.capture3(*python_args(audio_path))

        unless status.success?
          Rails.logger.warn("[speech_to_text] whisper failed (exit #{status.exitstatus}):\n#{stderr}")
          raise TranscriptionError, whisper_failure_message(stderr)
        end

        JSON.parse(stdout, symbolize_names: true)
      end
    rescue Timeout::Error
      raise TranscriptionError, "Whisper took longer than #{timeout_seconds} seconds and was stopped."
    rescue JSON::ParserError
      raise TranscriptionError, "Whisper returned an unreadable response."
    end

    def python_args(audio_path)
      args = [
        python_bin, SCRIPT_PATH.to_s,
        "--model", model,
        "--device", device,
        "--compute-type", compute_type,
        "--beam-size", DEFAULT_BEAM_SIZE.to_s,
        audio_path
      ]
      args.insert(args.index("--beam-size"), "--language", language) if language
      args
    end

    def whisper_failure_message(stderr)
      reason = stderr.to_s.strip.lines.last.to_s.strip
      "Speech-to-text failed. Whisper could not transcribe this audio" +
        (reason.present? ? " (#{reason.first(160)})." : ".")
    end

    # ---------------------------------------------------------------- input

    def write_input_tempfile
      file = Tempfile.create([ "stt_audio", audio_extension ])
      file.binmode
      file.write(decoded_audio)
      file.flush
      file
    rescue SpeechToText::Error
      cleanup(file)
      raise
    rescue StandardError
      cleanup(file)
      raise UnsupportedFormatError, "Could not read the audio payload (unsupported or corrupted audio)."
    end

    def decoded_audio
      match = DATA_URI_PATTERN.match(@audio_data)
      payload = match ? match[:payload] : @audio_data
      Base64.strict_decode64(payload)
    rescue ArgumentError
      raise UnsupportedFormatError, "Could not decode the audio payload."
    end

    # The input extension for the temp file: from the data-URI mime type when
    # present, otherwise from the original filename (browsers often leave the
    # mime type empty for .opus uploads).
    def audio_extension
      mime = @audio_data.match(/\Adata:(audio\/[a-z0-9.+-]+)/)&.[](1)
      key = MIME_EXTENSIONS[mime.to_s] || File.extname(@filename).delete(".").downcase.presence
      extension = SUPPORTED_EXTENSIONS[key]
      extension || raise(UnsupportedFormatError,
        "Unsupported audio format. Use OGG, OPUS, M4A, MP3, WAV or WEBM.")
    end
  end
end
