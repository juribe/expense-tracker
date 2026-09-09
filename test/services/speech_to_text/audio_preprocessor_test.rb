# frozen_string_literal: true

require "test_helper"

module SpeechToText
  # Audio preprocessing must always produce the exact WAV faster-whisper needs:
  # 16 kHz, mono, PCM, loudness-normalized. The FFmpeg invocation is asserted
  # directly; the live FFmpeg run is skipped when FFmpeg is not installed.
  class AudioPreprocessorTest < ActiveSupport::TestCase
    test "the ffmpeg command normalizes to 16 kHz mono WAV" do
      args = AudioPreprocessor.new(audio_path: "input.ogg").ffmpeg_args("input.ogg", "output.wav")

      assert_equal "ffmpeg", File.basename(AudioPreprocessor.bin)
      assert_includes args, "-af"
      assert_equal "loudnorm=I=-16:TP=-1.5:LRA=11", args[args.index("-af") + 1]
      assert_equal "16000", args[args.index("-ar") + 1]
      assert_equal "1", args[args.index("-ac") + 1]
      assert_equal "wav", args[args.index("-f") + 1]
      assert_equal "pcm_s16le", args[args.index("-c:a") + 1]
      assert_equal "output.wav", args.last
    end

    test "FFMPEG_BIN overrides the binary path (MacPorts/homebrew installs)" do
      with_env("FFMPEG_BIN" => "/opt/local/bin/ffmpeg") do
        assert_equal "/opt/local/bin/ffmpeg", AudioPreprocessor.bin
      end
    end

    test "a missing or failing ffmpeg raises PreprocessingError and cleans up" do
      with_env("FFMPEG_BIN" => "/nonexistent/ffmpeg") do
        error = assert_raises(PreprocessingError) { AudioPreprocessor.call(audio_path: "input.ogg") }
        assert_match(/ffmpeg|not available|No such file/i, error.message)
      end
    end

    # Live verification: an 8 kHz stereo tone is converted to 16 kHz mono PCM.
    test "converts an 8 kHz stereo tone into a 16 kHz mono WAV" do
      skip "ffmpeg is not installed" unless AudioPreprocessor.available?

      input = Tempfile.create([ "stt_test", ".wav" ])
      output = nil
      begin
        stdout, stderr, status = Open3.capture3(
          AudioPreprocessor.bin, "-hide_banner", "-loglevel", "error",
          "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=8000:duration=0.5",
          "-ac", "2", "-y", input.path
        )
        raise stderr unless status.success?

        output = AudioPreprocessor.call(audio_path: input.path)
        header = File.binread(output.path, 44)

        assert_equal "RIFF", header[0, 4]
        assert_equal "WAVE", header[8, 4]
        assert_equal 1, header[22, 2].unpack1("v")             # channels: mono
        assert_equal 16_000, header[24, 4].unpack1("V")        # sample rate
        assert_equal 16, header[34, 2].unpack1("v")            # PCM 16-bit
      ensure
        input.close
        File.delete(input.path) if File.exist?(input.path)
        if output && !output.closed?
          output.close
          File.delete(output.path) if File.exist?(output.path)
        end
      end
    end
  end
end
