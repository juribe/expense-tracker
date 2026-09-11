# frozen_string_literal: true

# Namespace for the AI services. Business logic talks to Ai::Router or the
# task-specific services, never to a model or provider directly.
module Ai
  def self.configuration
    Configuration.new
  end
end
