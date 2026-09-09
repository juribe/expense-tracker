# frozen_string_literal: true

require "open3"

module SpeechToText
  # Converts any supported input audio into the exact format the Whisper
  # providers work best with: WAV, 16 kHz, mono, PCM, loudness-normalized.
  #
  # Directly transcribing raw OGG/Opus voice notes produced incorrect
  # transcripts during development; running everything through this
  # normalization first fixed them, so providers MUST NOT skip it.
  #
  #   wav = SpeechToText::AudioPreprocessor.call(audio_path: "/tmp/note.ogg")
  #
  # Returns an open Tempfile (the caller owns it and must unlink it). Raises
  # SpeechToText::PreprocessingError on any FFmpeg failure.
  class AudioPreprocessor
    # Full path override for non-PATH installs (e.g. MacPorts:
    # /opt/local/bin/ffmpeg), mirroring the TESSERACT_BIN convention.
    TARGET_SAMPLE_RATE = 16_000
    TARGET_CHANNELS = 1
    LOUDNESS_FILTER = "loudnorm=I=-16:TP=-1.5:LRA=11"

    class << self
      def call(audio_path:)
        new(audio_path: audio_path).call
      end

      def bin
        ENV.fetch("FFMPEG_BIN", "ffmpeg")
      end

      def available?
        system(bin, "-version", out: File::NULL, err: File::NULL) ? true : false
      end
    end

    def initialize(audio_path:)
      @audio_path = audio_path
    end

    def call
      output = Tempfile.create([ "stt_input", ".wav" ])
      stdout, stderr, status = Open3.capture3(*ffmpeg_args(@audio_path, output.path))
      raise PreprocessingError, ffmpeg_failure_message(stderr) unless status.success?

      output
    rescue Errno::ENOENT
      cleanup(output)
      raise PreprocessingError, "FFmpeg is not available (#{self.class.bin})."
    rescue StandardError
      cleanup(output)
      raise
    end

    # Tempfile.create returns a plain File on this Ruby, and File#unlink was
    # removed in recent versions — delete by path so both variants work.
    def cleanup(file)
      return if file.nil?

      file.close unless file.closed?
      File.delete(file.path) if File.exist?(file.path)
    rescue StandardError
      nil
    end

    # Exposed for tests and provider debugging: the exact FFmpeg invocation.
    def ffmpeg_args(input_path, output_path)
      [
        self.class.bin, "-hide_banner", "-loglevel", "error",
        "-i", input_path,
        "-af", LOUDNESS_FILTER,
        "-ar", TARGET_SAMPLE_RATE.to_s,
        "-ac", TARGET_CHANNELS.to_s,
        "-f", "wav", "-c:a", "pcm_s16le",
        "-y", output_path
      ]
    end

    private

    # FFmpeg's stderr can be very long; the last lines carry the actual error
    # reason, so keep a short tail for the application-level message and log
    # the whole thing.
    def ffmpeg_failure_message(stderr)
      Rails.logger.warn("[speech_to_text] ffmpeg preprocessing failed:\n#{stderr}")
      reason = stderr.to_s.strip.lines.last.to_s.strip
      reason.presence || "ffmpeg could not process the audio."
    end
  end
end
