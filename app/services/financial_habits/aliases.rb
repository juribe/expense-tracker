# frozen_string_literal: true

module FinancialHabits
  IncomeSpendingAnalyzer = IncomeSpendingPatternAnalyzer
  IncomeSpending = IncomeSpendingPatternAnalyzer
  SpendingTimeAnalyzer = SpendingTimePatternAnalyzer
  SpendingTime = SpendingTimePatternAnalyzer
  MerchantAnalyzer = MerchantFrequencyAnalyzer
  MerchantFrequency = MerchantFrequencyAnalyzer
  RecurrentMerchantAnalyzer = MerchantFrequencyAnalyzer
  CreditUsageAnalyzer = CreditUsagePatternAnalyzer
  CreditUsage = CreditUsagePatternAnalyzer
  BehaviorChange = BehaviorChangeAnalyzer
  BehaviorChangeAnalyzer = BehaviorChangeAnalyzer
  PlanningOpportunity = PlanningOpportunityAnalyzer
  Planning = PlanningOpportunityAnalyzer
end

IncomeSpendingAnalyzer = FinancialHabits::IncomeSpendingPatternAnalyzer unless defined?(IncomeSpendingAnalyzer)
SpendingTimeAnalyzer = FinancialHabits::SpendingTimePatternAnalyzer unless defined?(SpendingTimeAnalyzer)
MerchantAnalyzer = FinancialHabits::MerchantFrequencyAnalyzer unless defined?(MerchantAnalyzer)
CreditUsageAnalyzer = FinancialHabits::CreditUsagePatternAnalyzer unless defined?(CreditUsageAnalyzer)