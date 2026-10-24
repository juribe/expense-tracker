# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "etc"
require_relative "support/fake_ai_provider"

# Never inherit AI provider configuration from the developer's .env:
# tests must make no real AI calls. Tests that exercise AI routing set the
# keys they need explicitly (with_env) and stub providers.
%w[
  MISTRAL_API_KEY MISTRAL_MODEL MISTRAL_BASE_URL MISTRAL_VISION_MODEL
  AI_STRONG_PROVIDER AI_STRONG_MODEL AI_STRONG_API_KEY AI_STRONG_BASE_URL
  AI_CHEAP_PROVIDER AI_CHEAP_MODEL AI_CHEAP_BASE_URL AI_CHEAP_API_KEY
  AI_CHEAP_CONFIDENCE_THRESHOLD AI_DETERMINISTIC_THRESHOLD
  AI_DISABLE_STRONG_TIER
  OPENROUTER_API_KEY OPENROUTER_BASE_URL OPENROUTER_SITE_URL OPENROUTER_APP_NAME
  FLEX_API_KEY FLEX_BASE_URL
  EXPENSES_FORCE_VISION
].each { |key| ENV.delete(key) }

# Never inherit outbound WhatsApp (Meta Graph API) delivery credentials from
# the developer's .env either: a test that forgets to stub ReplySender must
# no-op instead of making a real HTTP request and retrying with backoff.
# ReplySender-specific tests set the keys they need themselves (with_env or
# stubbing ENV.[]).
%w[WHATSAPP_ACCESS_TOKEN WHATSAPP_BUSINESS_PHONE_NUMBER_ID].each { |key| ENV.delete(key) }

# Chooses how many forked workers run the suite. Each worker boots a full
# Rails app (~2 GB), so grading workers only by CPU count makes small machines
# thrash (GC/swap) instead of speeding up. Cap by available RAM; set
# PARALLEL_WORKERS to override, or DISABLE_PARALLEL_TESTS=1 to run serially.
module TestParallelism
  BYTES_PER_WORKER = 2 * 1024**3
  FALLBACK_WORKERS = 4

  def self.workers(cpus: Etc.nprocessors, memory_bytes: available_memory_bytes)
    override = ENV["PARALLEL_WORKERS"].presence
    return override.to_i if override
    return [ cpus, FALLBACK_WORKERS ].min if memory_bytes.nil?

    [ [ cpus, (memory_bytes / BYTES_PER_WORKER).floor ].min, 1 ].max
  end

  def self.available_memory_bytes
    cgroup_memory_limit || linux_memory_bytes || macos_memory_bytes
  rescue StandardError
    nil
  end

  # Container memory limits (cgroup v2 then v1). A very large sentinel value
  # means "unlimited"; treat it as unknown.
  def self.cgroup_memory_limit
    %w[/sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes].each do |path|
      next unless File.readable?(path)

      value = File.read(path).strip
      next if value == "max"

      bytes = value.to_i
      return bytes if bytes.positive? && bytes < 10**15
    end

    nil
  end

  def self.linux_memory_bytes
    match = File.read("/proc/meminfo")[/^MemTotal:\s+(\d+)\s+kB/, 1]
    match && match.to_i * 1024
  rescue Errno::ENOENT
    nil
  end

  def self.macos_memory_bytes
    return nil unless RUBY_PLATFORM.include?("darwin")

    bytes = `sysctl -n hw.memsize 2>/dev/null`.to_i
    bytes.positive? ? bytes : nil
  rescue StandardError
    nil
  end
end

module ActiveSupport
  class TestCase
    parallelize(workers: TestParallelism.workers) unless ENV["DISABLE_PARALLEL_TESTS"] == "1"

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
      user.confirm if user.respond_to?(:confirm) && user.respond_to?(:confirmed?) && !user.confirmed?
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

# Bullet raises on N+1 queries and unused eager loading detected during
# integration tests (each index page in the sidebar is exercised here).
# start_request runs on the first HTTP request, not in setup, so records
# created while seeding are not registered as "impossible" (Bullet exempts
# in-thread created objects, which would mask their real N+1s).
# Bullet is disabled in test by default (see config/initializers/bullet.rb);
# with BULLET=1 the hook below collects normally again.
module BulletIntegrationHook
  def process(*)
    Bullet.start_request unless Bullet.start? if Bullet.enable?
    super
  end

  def teardown
    super
    return unless Bullet.enable?

    Bullet.raise = true
    Bullet.perform_out_of_channel_notifications if Bullet.notification?
    Bullet.raise = false
    Bullet.end_request
  end
end

module ActionDispatch
  class IntegrationTest
    prepend BulletIntegrationHook
  end
end

# With email confirmation enabled, test users created in setups must be confirmed
# before they can authenticate. Confirm them transparently when tests call
# Devise's sign_in helper so existing suites keep passing; direct session POSTs
# (which exercise the real authentication path) are unaffected.
module Devise
  module Test
    module IntegrationHelpers
      alias_method :__original_sign_in, :sign_in unless method_defined?(:__original_sign_in)

      def sign_in(resource, scope: nil)
        resource.confirm if resource.respond_to?(:confirm) && resource.respond_to?(:confirmed?) && !resource.confirmed?
        __original_sign_in(resource, scope: scope)
      end
    end
  end
end
