# frozen_string_literal: true

require "test_helper"

# TestParallelism picks the number of forked test workers from the machine's
# available memory. Each worker boots a full Rails app, so oversubscribing on
# a small machine causes GC/swap thrashing instead of speedups.
class TestParallelismTest < ActiveSupport::TestCase
  GIGABYTE = 1024**3

  test "caps workers by available memory" do
    assert_equal 4, TestParallelism.workers(cpus: 8, memory_bytes: 8 * GIGABYTE)
    assert_equal 8, TestParallelism.workers(cpus: 8, memory_bytes: 32 * GIGABYTE)
    assert_equal 2, TestParallelism.workers(cpus: 4, memory_bytes: 4 * GIGABYTE)
  end

  test "never exceeds the number of processors" do
    assert_equal 2, TestParallelism.workers(cpus: 2, memory_bytes: 64 * GIGABYTE)
  end

  test "never returns fewer than one worker" do
    assert_equal 1, TestParallelism.workers(cpus: 8, memory_bytes: 512 * 1024**2)
  end

  test "falls back to at most four workers when memory is unknown" do
    assert_equal 4, TestParallelism.workers(cpus: 8, memory_bytes: nil)
    assert_equal 2, TestParallelism.workers(cpus: 2, memory_bytes: nil)
  end

  test "PARALLEL_WORKERS overrides the computed count" do
    with_env("PARALLEL_WORKERS" => "3") do
      assert_equal 3, TestParallelism.workers(cpus: 8, memory_bytes: 32 * GIGABYTE)
    end
  end
end
