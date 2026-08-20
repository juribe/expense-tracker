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
  end
end


require "capybara/rails"
require "capybara/minitest"


require "capybara/rails"
require "capybara/minitest"


require "capybara/rails"
require "capybara/minitest"


require "capybara/rails"
require "capybara/minitest"


require "capybara/rails"
require "capybara/minitest"
