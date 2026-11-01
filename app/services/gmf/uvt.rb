# frozen_string_literal: true

module Gmf
  # Gmf::Uvt
  # Centralized access to the annual UVT value and the derived exemption limit.
  #
  # Methods: .value_for(year), .exemption_limit(year)
  #
  # Example: Gmf::Uvt.exemption_limit(2026) # => 350 * UVT(2026)
  module Uvt
    def self.value_for(year)
      GmfUvtYear.value_for(year)
    end

    def self.exemption_limit(year)
      GmfUvtYear.exemption_limit(year)
    end
  end
end
