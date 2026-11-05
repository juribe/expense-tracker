# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesAnalysisStateTest < ActiveSupport::TestCase
  setup do
    @previous_cache = SavingsOpportunities::AnalysisState.cache
    SavingsOpportunities::AnalysisState.cache = ActiveSupport::Cache::MemoryStore.new
    @user_id = SecureRandom.uuid
  end

  teardown do
    SavingsOpportunities::AnalysisState.cache = @previous_cache
  end

  test "returns idle when there is no stored state" do
    assert_equal "idle", SavingsOpportunities::AnalysisState.read(@user_id)
  end

  test "reads the last written state" do
    SavingsOpportunities::AnalysisState.write(@user_id, "ready")

    assert_equal "ready", SavingsOpportunities::AnalysisState.read(@user_id)
  end

  test "keeps a recent pending state" do
    SavingsOpportunities::AnalysisState.write(@user_id, "pending")

    assert_equal "pending", SavingsOpportunities::AnalysisState.read(@user_id)
  end

  test "treats a stale pending state as failed" do
    SavingsOpportunities::AnalysisState.cache.write(
      SavingsOpportunities::AnalysisState.state_key(@user_id),
      { "state" => "pending", "at" => 10.minutes.ago.iso8601 }
    )

    assert_equal "failed", SavingsOpportunities::AnalysisState.read(@user_id)
  end

  test "the lock prevents duplicate acquisitions" do
    assert SavingsOpportunities::AnalysisState.acquire_lock(@user_id)
    refute SavingsOpportunities::AnalysisState.acquire_lock(@user_id)
  end
end
