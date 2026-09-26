# 500-case expense parser benchmark (diagnostic only).
#
# Runs the case list from /Users/joseuribe/Downloads/expense_parser_500_case_benchmark.md
# through the CURRENT ExpenseResolver pipeline exactly as a real user would,
# without modifying production code, prompts, models, or records.
#
#   bin/rails runner script/experiments/benchmark_500.rb
#
# Uses the established experiment user (cuenta davibank / tarjeta davibank /
# efectivo). Our project rules stand over the document where they differ:
# bare "Davibank" must never silently resolve (review flag required),
# refunds are never netted silently, suggestions are flagged, and the
# "efectivo" source exists because the case list references it.
#
# Output: script/experiments/benchmark_500_results.json (checkpointed every
# 10 cases and resumable — an interrupted run continues where it stopped).
require "json"

CASES_FILE = Pathname.new("/Users/joseuribe/Downloads/expense_parser_500_case_benchmark.md")
RESULTS_FILE = Rails.root.join("script/experiments/benchmark_500_results.json")
CHECKPOINT_EVERY = 10

lines = CASES_FILE.read.lines
CASES = lines.filter_map do |line|
  match = line.match(/^\s*(\d+)\.\s+`(.+?)`\s*$/)
  match ? [ match[1].to_i, match[2] ] : nil
end.sort_by(&:first)

raise "expected 500 cases, got #{CASES.size}" unless CASES.size == 500

user = User.find_by(email: "baseline-experiment@example.com") || User.create!(
  name: "Baseline Experiment", email: "baseline-experiment@example.com", password: "password123"
)

if user.money_sources.count.zero?
  cuenta = user.money_sources.create!(name: "cuenta davibank", kind: "account")
  cuenta.ensure_recognition.replace_identifiers(keyword: [ "cuenta davibank" ])
  tarjeta = user.money_sources.create!(name: "tarjeta davibank", kind: "credit_card")
  tarjeta.ensure_recognition.replace_identifiers(keyword: [ "tarjeta davibank", "tarjeta" ])
  efectivo = user.money_sources.create!(name: "efectivo", kind: "cash")
  efectivo.ensure_recognition.replace_identifiers(keyword: [ "efectivo", "dinero", "plata" ])
end

previous = if RESULTS_FILE.exist?
  JSON.parse(RESULTS_FILE.read)
else
  []
end
done = previous.map { |row| row["case"] }.to_set
results = previous
puts "resuming: #{done.size} cases already done" if done.any?

CASES.each do |number, text|
  next if done.include?(number)

  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  service_result = ExpenseResolver::Service.call(text: text, user: user)
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)

  candidates = service_result.success? ? service_result.result : []
  entries = candidates.map do |candidate|
    {
      description: candidate.description,
      amount: candidate.amount&.to_f,
      date: candidate.date&.iso8601,
      category_id: candidate.category_id,
      category_name: candidate.category_name,
      suggested_category_name: candidate.suggested_category_name,
      money_source_name: candidate.money_source_name,
      money_source_id: candidate.money_source_id,
      money_source_source: candidate.money_source_source,
      classification_source: candidate.classification_source,
      confidence: candidate.confidence,
      warnings: candidate.warnings.to_a
    }
  end

  results << {
    "case" => number,
    "input" => text,
    "ok" => service_result.success?,
    "error" => service_result.success? ? nil : service_result.errors,
    "latency_seconds" => elapsed,
    "engine" => candidates.first&.classification_source,
    "expenses" => entries
  }
  puts "case #{number}: #{service_result.success? ? "ok" : "FAIL"} (#{elapsed}s, #{entries.size} expenses)"

  if number % CHECKPOINT_EVERY == 0
    RESULTS_FILE.dirname.mkpath
    File.write(RESULTS_FILE, JSON.pretty_generate(results))
  end
end

File.write(RESULTS_FILE, JSON.pretty_generate(results))
puts "Wrote #{results.size} cases to #{RESULTS_FILE}"
