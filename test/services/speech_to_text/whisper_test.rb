# frozen_string_literal: true

require "test_helper"

module SpeechToText
  # The Whisper provider is tested WITHOUT executing Python or downloading
  # models: the FFmpeg preprocessor and the Python process are stubbed at
  # their seams (AudioPreprocessor.call / Open3.capture3), and the payload is
  # what a successful faster-whisper run prints.
  class WhisperTest < ActiveSupport::TestCase
    AUDIO = "data:audio/ogg;base64,#{Base64.strict_encode64('OGGDATABYTES')}"
    WHISPER_PAYLOAD = {
      ok: true,
      text: "Este es un ejemplo.",
      language: "es",
      language_probability: 0.98,
      duration: 5.2
    }.freeze

    FakeStatus = Struct.new(:exitstatus) do
      def success?
        exitstatus.zero?
      end
    end

    setup do
      @saved = %w[WHISPER_MODEL WHISPER_LANGUAGE WHISPER_DEVICE WHISPER_COMPUTE_TYPE].to_h do |key|
        [ key, ENV.delete(key) ]
      end
    end

    teardown do
      @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    def stub_pipeline(payload: WHISPER_PAYLOAD, exit_status: 0, stderr: "",
                      preprocessing: ->(**_kwargs) { Tempfile.new("wav") })
      stub_method(Open3, :capture3, ->(*_args) {
        [ payload.nil? ? "" : JSON.dump(payload), stderr, FakeStatus.new(exit_status) ]
      }) do
        stub_method(AudioPreprocessor, :call, preprocessing) do
          yield
        end
      end
    end

    test "successful transcription returns a normalized result" do
      stub_pipeline do
        result = Whisper.call(audio_data: AUDIO, filename: "note.ogg")

        assert_instance_of Result, result
        assert_equal "Este es un ejemplo.", result.text
        assert_equal "es", result.language
        assert_equal 0.98, result.language_probability
        assert_equal 5.2, result.duration
        assert_equal "whisper", result.provider
        assert_equal "small", result.model
        assert_not result.empty_transcript?
      end
    end

    test "result metadata carries the effective configuration" do
      with_env("WHISPER_MODEL" => "base", "WHISPER_LANGUAGE" => "es") do
        stub_pipeline do
          result = Whisper.call(audio_data: AUDIO, filename: "note.ogg")

          assert_equal "base", result.model
          assert_equal "es", result.metadata[:configured_language]
          assert_equal "cpu", result.metadata[:device]
          assert_equal "int8", result.metadata[:compute_type]
          assert_equal 5, result.metadata[:beam_size]
        end
      end
    end

    test "no WHISPER_LANGUAGE configured means automatic language detection" do
      stub_pipeline do
        result = Whisper.call(audio_data: AUDIO, filename: "note.ogg")

        assert_equal "es", result.language # detected by whisper, reported in the result
        assert_nil result.metadata[:configured_language]
      end
    end

    test "an empty transcript is reported, not extracted" do
      stub_pipeline(payload: WHISPER_PAYLOAD.merge(text: "  ")) do
        result = Whisper.call(audio_data: AUDIO, filename: "note.ogg")

        assert_equal "", result.text
        assert result.empty_transcript?
      end
    end

    test "unsupported audio formats raise UnsupportedFormatError" do
      stub_pipeline do
        error = assert_raises(UnsupportedFormatError) do
          Whisper.call(audio_data: "data:video/mp4;base64,AAAA", filename: "clip.mp4")
        end
        assert_match(/Unsupported audio format/, error.message)
      end
    end

    test "unsupported formats are detected from the filename when the mime is generic" do
      stub_pipeline do
        error = assert_raises(UnsupportedFormatError) do
          Whisper.call(audio_data: "data:application/octet-stream;base64,AAAA", filename: "voice.aac")
        end
        assert_match(/Unsupported audio format/, error.message)
      end
    end

    test "corrupted payloads raise UnsupportedFormatError" do
      stub_pipeline do
        assert_raises(UnsupportedFormatError) do
          Whisper.call(audio_data: "data:audio/ogg;base64,!!!!not-base64!!!!", filename: "note.ogg")
        end
      end
    end

    test "preprocessing failures propagate as PreprocessingError" do
      stub_pipeline(preprocessing: ->(**_kwargs) { raise PreprocessingError, "ffmpeg could not process the audio." }) do
        error = assert_raises(PreprocessingError) { Whisper.call(audio_data: AUDIO, filename: "note.ogg") }
        assert_match(/ffmpeg/, error.message)
      end
    end

    test "a failing python process raises TranscriptionError without raw stack traces" do
      stub_pipeline(exit_status: 1, stderr: "Traceback (most recent call last):\n  File ...\nValueError: boom") do
        error = assert_raises(TranscriptionError) { Whisper.call(audio_data: AUDIO, filename: "note.ogg") }
        assert_match(/Whisper could not transcribe/, error.message)
        refute_match(/Traceback/, error.message)
      end
    end

    test "an unreadable python response raises TranscriptionError" do
      stub_method(Open3, :capture3, ->(*_args) { [ "not json", "", FakeStatus.new(0) ] }) do
        stub_method(AudioPreprocessor, :call, ->(**_kwargs) { Tempfile.new("wav") }) do
          assert_raises(TranscriptionError) { Whisper.call(audio_data: AUDIO, filename: "note.ogg") }
        end
      end
    end

    test "the python invocation carries model, device, compute type and configured language" do
      with_env("WHISPER_LANGUAGE" => "es") do
        args = Whisper.new(audio_data: AUDIO, filename: "note.ogg").send(:python_args, "/tmp/preprocessed.wav")

        script = args.find { |arg| arg.to_s.end_with?("whisper_transcribe.py") }
        assert script.present?
        assert_equal "small", args[args.index("--model") + 1]
        assert_equal "cpu", args[args.index("--device") + 1]
        assert_equal "int8", args[args.index("--compute-type") + 1]
        assert_equal "5", args[args.index("--beam-size") + 1]
        assert_equal "es", args[args.index("--language") + 1]
        assert_equal "/tmp/preprocessed.wav", args.last # the preprocessed WAV is transcribed
      end
    end

    test "python args omit --language when detection is automatic" do
      args = Whisper.new(audio_data: AUDIO, filename: "note.ogg").send(:python_args, "/tmp/preprocessed.wav")

      refute_includes args, "--language"
    end
  end
end
