# frozen_string_literal: true

module WebauthnChallenge
  TTL = 5.minutes

  module_function

  def fresh?(timestamp)
    timestamp.present? && Time.zone.at(timestamp.to_i) >= TTL.ago
  end
end
