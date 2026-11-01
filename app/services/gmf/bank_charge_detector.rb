# frozen_string_literal: true

module Gmf
  class BankChargeDetector
    PATTERNS = [
      /4\s*x\s*1000/i,
      /4x1\.000/i,
      /gravamen/i,
      /\bgmf\b/i,
      /4\s*por\s*mil/i
    ].freeze

    def self.bank_charge?(description)
      text = description.to_s
      PATTERNS.any? { |pattern| pattern.match?(text) }
    end
  end
end
