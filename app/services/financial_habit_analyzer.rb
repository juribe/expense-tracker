# frozen_string_literal: true

# Compatibility base class / interface for analyzers.
class FinancialHabitAnalyzer
  def self.analyzers
    FinancialHabits::Analysis.instance_methods(false)
  end
end

module FinancialHabits
  FinancialHabitAnalyzer = ::FinancialHabitAnalyzer unless defined?(FinancialHabitAnalyzer)
end