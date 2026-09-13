# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/fake_ai_provider"

# Never inherit AI provider configuration from the developer's .env:
# tests must make no real AI calls. Tests that exercise AI routing set the
# keys they need explicitly (with_env) and stub providers.
%w[
  MISTRAL_API_KEY MISTRAL_MODEL MISTRAL_BASE_URL MISTRAL_VISION_MODEL
  AI_STRONG_PROVIDER AI_STRONG_MODEL AI_STRONG_API_KEY AI_STRONG_BASE_URL
  AI_CHEAP_PROVIDER AI_CHEAP_MODEL AI_CHEAP_BASE_URL AI_CHEAP_API_KEY
  AI_CHEAP_CONFIDENCE_THRESHOLD AI_DETERMINISTIC_THRESHOLD
  OPENROUTER_API_KEY OPENROUTER_BASE_URL OPENROUTER_SITE_URL OPENROUTER_APP_NAME
  FLEX_API_KEY FLEX_BASE_URL
].each { |key| ENV.delete(key) }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    module SlowTestTiming
      def run
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        super
      ensure
        dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        File.open("/tmp/slow_tests.#{Process.pid}.log", "a") { |f| f.puts "#{dt.round(2).to_s.rjust(8)}s #{self.class}##{self.name}" } if dt > 1.0
      end
    end

    prepend SlowTestTiming if ENV["SLOW_PROBE"] == "1"

    def sign_in_as(user)
      post user_session_path, params: { user: { email: user.email, password: "password123" } }
    end

    # Temporarily swaps the Active Job queue adapter (e.g. :test or :inline)
    # for the duration of the block, restoring the original afterwards.
    def with_active_job_adapter(adapter)
      original = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = adapter
      yield
    ensure
      ActiveJob::Base.queue_adapter = original
    end

    # Temporarily replaces a class/instance method for the duration of the
    # block. Pass a fixed return value or anything callable (it receives the
    # original arguments).
    def stub_method(owner, name, replacement = nil)
      handler = replacement.respond_to?(:call) ? replacement : ->(*_args) { replacement }
      original = owner.method(name)
      owner.define_singleton_method(name, &handler)
      yield
    ensure
      owner.define_singleton_method(name, original)
    end

    # Temporarily sets ENV variables (nil deletes them) for the duration of the block.
    def with_env(overrides)
      original = {}
      overrides.each do |key, value|
        original[key] = ENV[key]
        value.nil? ? ENV.delete(key) : ENV[key] = value.to_s
      end
      yield
    ensure
      original.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end
end
