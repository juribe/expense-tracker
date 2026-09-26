# Baseline experiment: runs 100 expense messages through the CURRENT
# ExpenseResolver pipeline as a real user would, and dumps the raw parsed
# candidates without correction.
#
#   bin/rails runner script/experiments/baseline_100.rb
#
# Uses a dedicated experiment user (cuenta davibank / tarjeta davibank /
# efectivo) so the stated money-source context exists without touching any
# real user's records. Output: script/experiments/baseline_100_results.json
require "json"

CASES = [
  # 1. Basic single expenses
  "Almuerzo 45.000",
  "Compré comida por 38.500",
  "Gasolina 150.000",
  "Café 8.500",
  "Restaurante 95.000",
  "Compré una camisa por 150.000",
  "Zapatos 220.000",
  "Parqueadero 15.000",
  "Mercado 280.000",
  "Pagué 120.000 de internet",
  # 2. Multiple expenses
  "Almuerzo 45.000 y café 8.000",
  "Comida 60.000 y parqueadero 15.000",
  "Desayuno 30.000, almuerzo 50.000 y cena 40.000",
  "Taxi 18.000, café 7.000 y almuerzo 42.000",
  "Supermercado 180.000 y farmacia 65.000",
  "Camisa 120.000 y zapatos 180.000",
  "Internet 120.000, celular 55.000 y Netflix 38.900",
  "Gasolina 150.000 y parqueadero 12.000",
  "Almuerzo 75.000 y postre 15.000",
  "Comida 40.000, transporte 20.000 y cine 30.000",
  # 3. Davibank ambiguous
  "Almuerzo 45.000 con Davibank",
  "Compré comida por 60.000 con Davibank",
  "Gasolina 150.000 con Davibank",
  "Restaurante 95.000 pagado con Davibank",
  "Compré zapatos por 220.000 usando Davibank",
  "Netflix 38.900 con Davibank",
  "Farmacia 75.000 con Davibank",
  "Mercado 200.000 con Davibank",
  "Taxi 25.000 con Davibank",
  "Pagué 100.000 de ropa con Davibank",
  # 4. Explicit Davibank account
  "Almuerzo 45.000 con la cuenta Davibank",
  "Comida 60.000 desde mi cuenta Davibank",
  "Gasolina 150.000 con mi cuenta de Davibank",
  "Restaurante 95.000 pagado desde la cuenta Davibank",
  "Compré zapatos por 220.000 con la cuenta de Davibank",
  "Netflix 38.900 desde mi cuenta Davibank",
  "Farmacia 75.000 con mi cuenta Davibank",
  "Mercado 200.000 desde la cuenta Davibank",
  "Taxi 25.000 con la cuenta Davibank",
  "Pagué 100.000 de ropa desde mi cuenta de Davibank",
  # 5. Explicit Davibank credit card
  "Almuerzo 45.000 con la tarjeta Davibank",
  "Comida 60.000 con mi tarjeta de crédito Davibank",
  "Gasolina 150.000 con la tarjeta de Davibank",
  "Restaurante 95.000 pagado con mi tarjeta Davibank",
  "Compré zapatos por 220.000 con la tarjeta de crédito Davibank",
  "Netflix 38.900 con la tarjeta Davibank",
  "Farmacia 75.000 con mi tarjeta de crédito Davibank",
  "Mercado 200.000 con la tarjeta Davibank",
  "Taxi 25.000 con mi tarjeta Davibank",
  "Pagué 100.000 de ropa con la tarjeta de crédito Davibank",
  # 6. Multiple expenses + ambiguous Davibank
  "Almuerzo 50.000 con Davibank y gasolina 100.000 en efectivo",
  "Supermercado 200.000 con Davibank y café 8.000 en efectivo",
  "Restaurante 120.000 con Davibank y parqueadero 15.000 en efectivo",
  "Compré zapatos por 180.000 con Davibank y una camisa por 100.000 con efectivo",
  "Netflix 38.900 con Davibank y Spotify 24.900 con Davibank",
  "Café 8.000 en efectivo, almuerzo 55.000 con Davibank y taxi 20.000",
  "Comida 80.000 con Davibank y ropa 150.000 con tarjeta",
  "Farmacia 75.000 con Davibank y supermercado 220.000 en efectivo",
  "Gasolina 150.000 con Davibank, almuerzo 45.000 con efectivo",
  "Pagué 100.000 de comida con Davibank y 50.000 de ropa con Davibank",
  # 7. Multiple expenses + explicit account/card
  "Almuerzo 50.000 con la cuenta Davibank y gasolina 100.000 con efectivo",
  "Supermercado 200.000 con la tarjeta Davibank y café 8.000 con la cuenta Davibank",
  "Restaurante 120.000 con la tarjeta de crédito Davibank y parqueadero 15.000 en efectivo",
  "Zapatos 180.000 con la tarjeta Davibank y camisa 100.000 con la cuenta Davibank",
  "Netflix 38.900 con la tarjeta Davibank y Spotify 24.900 con la cuenta Davibank",
  "Café 8.000 en efectivo, almuerzo 55.000 con la cuenta Davibank y taxi 20.000 con la tarjeta Davibank",
  "Comida 80.000 con la cuenta Davibank y ropa 150.000 con la tarjeta Davibank",
  "Farmacia 75.000 con la cuenta Davibank y supermercado 220.000 con la tarjeta Davibank",
  "Gasolina 150.000 con la tarjeta Davibank y almuerzo 45.000 con la cuenta Davibank",
  "Comida 100.000 con la cuenta Davibank y ropa 50.000 con la tarjeta Davibank",
  # 8. Dates + sources
  "Ayer gasté 45.000 en almuerzo con Davibank",
  "Ayer gasté 45.000 en almuerzo con la cuenta Davibank",
  "Ayer gasté 45.000 en almuerzo con la tarjeta Davibank",
  "Hoy compré comida por 35.000 con Davibank",
  "Hoy compré comida por 35.000 con la tarjeta de crédito Davibank",
  "El lunes pagué 120.000 de internet desde mi cuenta Davibank",
  "El martes compré zapatos por 180.000 con la tarjeta Davibank",
  "El viernes pagué 80.000 de restaurante con Davibank",
  "Ayer compré comida con Davibank por 50.000 y hoy gasolina por 100.000 con la tarjeta Davibank",
  "El lunes pagué 50.000 con la cuenta Davibank y el martes 80.000 con la tarjeta Davibank",
  # 9. Transfers
  "Pasé 500.000 de Davibank a Nequi",
  "Pasé 500.000 desde mi cuenta Davibank a Nequi",
  "Pasé 500.000 desde mi tarjeta Davibank a otra cuenta",
  "Transferí 300.000 de Davibank a mi cuenta de ahorros",
  "Moví 200.000 de Davibank a Nequi",
  "Recargué Nequi con 150.000 desde mi cuenta Davibank",
  "Le transferí 100.000 a mi esposa desde Davibank",
  "Pasé 80.000 de Davibank a Nequi y después gasté 30.000 en comida",
  "Transferí 500.000 desde mi cuenta Davibank y después pagué 70.000 de restaurante con la tarjeta Davibank",
  "Pasé 300.000 de Davibank a Nequi, gasté 50.000 en comida y luego pasé otros 100.000",
  # 10. Complex cases
  "Ayer salí con mi esposa: pagué 85.000 del restaurante con Davibank, 18.000 del parqueadero en efectivo y compré medicinas por 42.500 con la cuenta Davibank. También pasé 200.000 de Davibank a Nequi",
  "Hoy compré mercado por 180.000 con la tarjeta Davibank, pagué 35.000 de taxi en efectivo y almorcé por 65.000 con la cuenta Davibank",
  "El sábado gasté 120.000 en restaurante, 20.000 de parqueadero y 15.000 en café. El restaurante lo pagué con la cuenta Davibank y lo demás en efectivo",
  "Ayer pagué Netflix 38.900 con la tarjeta Davibank, Spotify 24.900 con Davibank y HBO 29.900 con la cuenta Davibank",
  "El lunes pasé 500.000 de Davibank a Nequi, gasté 80.000 en supermercado con la cuenta Davibank y después 35.000 en Didi Food con la tarjeta Davibank",
  "Compré tres cafés de 8.500, un almuerzo de 45.000 y después pagué 15.000 de parqueadero, todo con Davibank",
  "El viernes gasté 150.000 en ropa con la tarjeta Davibank, 80.000 en comida con la cuenta Davibank y 20.000 en taxi en efectivo",
  "Compré mercado por 200.000 con Davibank, pero me devolvieron 30.000 de unos productos. También pagué 45.000 de almuerzo con la tarjeta Davibank",
  "Ayer gasté 100.000 en comida con Davibank, bueno 90.000 porque nos hicieron descuento, y 25.000 de parqueadero con la cuenta Davibank. Hoy pasé 300.000 de Davibank a Nequi",
  "Ayer salí con mi familia: desayuno 45.000, tres almuerzos de 38.000 cada uno, dos cafés de 9.000 cada uno y parqueadero 18.000. El desayuno y los almuerzos los pagué con la cuenta Davibank, los cafés con efectivo y el parqueadero con la tarjeta Davibank. Además pasé 500.000 de Davibank a Nequi."
].freeze

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

  row = {
    case: index + 1,
    input: text,
    ok: service_result.success?,
    error: service_result.success? ? nil : service_result.errors,
    latency_seconds: elapsed,
    engine: candidates.first&.classification_source,
    expenses: entries
  }
  puts "case #{index + 1}: #{row[:ok] ? 'ok' : 'FAIL'} (#{elapsed}s, #{entries.size} expenses)"
  row
end

dir = Rails.root.join("script/experiments")
dir.mkpath
File.write(dir.join("baseline_100_results.json"), JSON.pretty_generate(results))
puts "Wrote #{results.size} cases to script/experiments/baseline_100_results.json"
