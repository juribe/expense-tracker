require "test_helper"
require "csv"

class ScratchEnqueueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "scratch enqueue" do
    user = User.create!(email: "scratch-enqueue@example.com", password: "password123")
    csv = CSV.generate do |c|
      c << [ "message", "expected_json" ]
      c << [ "me gasté 20mil", { "intent" => "expense", "amount" => 20_000 }.to_json ]
    end

    with_active_job_adapter(:test) do
      ExpensePlayground::Evaluations::Runner.start(
        user: user, content: csv, filename: "g.csv", provider: "openrouter", model: "m"
      )
      puts "HELPER=#{enqueued_jobs.map { |j| j[:job].class.name }}"
    end
  end
end