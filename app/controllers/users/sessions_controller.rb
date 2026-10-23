# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  # Credential guessing is the cheapest attack on the app: check the counter
  # before Devise validates anything. The counter must not depend on the user
  # (a wrong guess must not be able to lock someone out), so it is per IP:
  # limits are loose in dev, strict in production. Names keep the two branch
  # definitions from sharing one rate-limit key.
  rate_limit to: 100, within: 1.minute, only: :create, name: "login",
             store: RateLimitProxy.new, if: -> { !Rails.env.production? }
  rate_limit to: 10, within: 1.minute, only: :create, name: "login",
             store: RateLimitProxy.new, if: -> { Rails.env.production? }
end
