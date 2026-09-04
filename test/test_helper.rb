# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

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
