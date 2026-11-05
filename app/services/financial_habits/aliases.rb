# frozen_string_literal: true

module FinancialHabits
  # Convenience names kept inside their own namespace so Zeitwerk can eager
  # load this file without expecting the aliases to live at the module root.
  module Aliases
    IncomeSpendingAnalyzer = FinancialHabits::IncomeSpendingPatternAnalyzer
    IncomeSpending = FinancialHabits::IncomeSpendingPatternAnalyzer
    SpendingTimeAnalyzer = FinancialHabits::SpendingTimePatternAnalyzer
    SpendingTime = FinancialHabits::SpendingTimePatternAnalyzer
    MerchantAnalyzer = FinancialHabits::MerchantFrequencyAnalyzer
    MerchantFrequency = FinancialHabits::MerchantFrequencyAnalyzer
    RecurrentMerchantAnalyzer = FinancialHabits::MerchantFrequencyAnalyzer
    CreditUsageAnalyzer = FinancialHabits::CreditUsagePatternAnalyzer
    CreditUsage = FinancialHabits::CreditUsagePatternAnalyzer
    BehaviorChange = FinancialHabits::BehaviorChangeAnalyzer
    PlanningOpportunity = FinancialHabits::PlanningOpportunityAnalyzer
    Planning = FinancialHabits::PlanningOpportunityAnalyzer
  end

  IncomeSpendingAnalyzer = Aliases::IncomeSpendingAnalyzer
  IncomeSpending = Aliases::IncomeSpending
  SpendingTimeAnalyzer = Aliases::SpendingTimeAnalyzer
  SpendingTime = Aliases::SpendingTime
  MerchantAnalyzer = Aliases::MerchantAnalyzer
  MerchantFrequency = Aliases::MerchantFrequency
  RecurrentMerchantAnalyzer = Aliases::RecurrentMerchantAnalyzer
  CreditUsageAnalyzer = Aliases::CreditUsageAnalyzer
  CreditUsage = Aliases::CreditUsage
  BehaviorChange = Aliases::BehaviorChange
  PlanningOpportunity = Aliases::PlanningOpportunity
  Planning = Aliases::Planning
end

IncomeSpendingAnalyzer = FinancialHabits::IncomeSpendingAnalyzer unless defined?(IncomeSpendingAnalyzer)
SpendingTimeAnalyzer = FinancialHabits::SpendingTimeAnalyzer unless defined?(SpendingTimeAnalyzer)
MerchantAnalyzer = FinancialHabits::MerchantAnalyzer unless defined?(MerchantAnalyzer)
CreditUsageAnalyzer = FinancialHabits::CreditUsageAnalyzer unless defined?(CreditUsageAnalyzer)