# Experiment harness: runs representative expense messages through the CURRENT
# ExpenseResolver pipeline exactly as the app would (deterministic pass first,
# AI escalation when the confidence gate fails) and dumps the raw parsed
# candidates without any manual correction.
#
#   bin/rails runner script/expense_parsing_experiment.rb
#
# Output: script/experiments/expense_parsing_results.json
require "json"

CASES = [
  "Ayer gasté 45.000 en almuerzo, 18.000 en un taxi y 12.500 en café, todo con Davibank.",
  "Pagué 80.000 del supermercado con tarjeta Infinite y 25.000 de gasolina en efectivo.",
  "El lunes pagué 120.000 de internet y hoy compré 35.000 de comida.",
  "Salí con mi esposa al centro comercial, primero almorzamos por 95.000 y después compré una camisa de 140.000 con la tarjeta.",
  "Compré mercado por 180.000: 120.000 de comida y 60.000 de productos de limpieza.",
  "Pasé 500.000 de Davibank a Nequi y después gasté 75.000 en Didi Food.",
  "Didi 32.000",
  "Netflix me cobró 38.900 de la tarjeta.",
  "Pagué 2.818.000 de la cuota del carro.",
  "Almuerzo 72.000 más 10.000 de propina, pagado con tarjeta.",
  "Hoy me gasté como 60 lucas comiendo con la familia y otras 20 en parqueadero.",
  "Compré zapatos por 180.000, bueno, fueron 160.000 al final, con Infinite.",
  "Tres cafés de 8.500 cada uno y un sándwich de 22.000.",
  "Compré una camisa por 120.000 y me devolvieron 30.000 porque tenía un descuento.",
  "Ayer salí con mi esposa: pagué 85.000 del restaurante con Infinite, 18.000 del parqueadero en efectivo y después compré unas medicinas por 42.500 con Davibank. También pasé 200.000 de Davibank a Nequi para tener efectivo."
].freeze

user = User.find(6)

results = CASES.each_with_index.map do |text, index|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  service_result = ExpenseResolver::Service.call(text: text, user: user)
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)

  candidates = service_result.success? ? service_result.result : []
  entries = candidates.map do |candidate|
    {
      description: candidate.description,
      amount: candidate.amount&.to_i,
      date: candidate.date&.iso8601,
      category_name: candidate.category_name,
      category_id: candidate.category_id,
      suggested_category_name: candidate.suggested_category_name,
      money_source_name: candidate.money_source_name,
      money_source_id: candidate.money_source_id,
      money_source_source: candidate.money_source_source,
      classification_source: candidate.classification_source,
      confidence: candidate.confidence,
      warnings: candidate.warnings.to_a
    }
  end

  {
    case: index + 1,
    input: text,
    ok: service_result.success?,
    error: service_result.success? ? nil : service_result.errors,
    latency_seconds: elapsed,
    engine: candidates.first&.classification_source,
    expenses: entries
  }
end

dir = Rails.root.join("script/experiments")
dir.mkpath
File.write(dir.join("expense_parsing_results.json"), JSON.pretty_generate(results))
puts "Wrote #{results.size} cases to script/experiments/expense_parsing_results.json"
