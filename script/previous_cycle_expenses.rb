# frozen_string_literal: true

# Clones a user's current pay-cycle expenses into the previous pay cycle: dates
# shifted one month back and amounts 30% lower. Rows are inserted with
# insert_all so no model callbacks run: money source balances, spending alerts,
# GMF flows and recurring flags stay untouched.
#
# Every generated row carries a unique tag in transactions.tags, so the DELETE
# mode removes exactly those rows and nothing else.
#
#   bin/rails runner script/previous_cycle_expenses.rb                  # dry run
#   APPLY=1 bin/rails runner script/previous_cycle_expenses.rb          # insert
#   DELETE=1 bin/rails runner script/previous_cycle_expenses.rb         # preview deletion
#   APPLY=1 DELETE=1 bin/rails runner script/previous_cycle_expenses.rb # delete
#
# Delete only through this script: destroying these rows from the UI would run
# the balance callbacks that were intentionally skipped on insert.
#
# Idempotent per cycle: re-running refuses to duplicate rows that already carry
# the same tag.

USER_EMAIL = "jse.uribe@gmail.com"
AMOUNT_FACTOR = BigDecimal("0.7")

def money(value)
  format("%.2f", value)
end

def adjust_counters(category_counts, money_source_counts, sign)
  category_counts.each do |category_id, count|
    Category.where(id: category_id).update_all([ "expenses_count = expenses_count + ?", sign * count ])
  end
  money_source_counts.each do |money_source_id, count|
    MoneySource.where(id: money_source_id).update_all([ "transactions_count = transactions_count + ?", sign * count ])
  end
end

user = User.find_by!(email: USER_EMAIL)
current_cycle = PayCycle.current(user)
previous_cycle = PayCycle.previous(user)
tag = "simulado_ciclo_anterior_#{previous_cycle.starts.iso8601}"

tagged = Transaction.where(user_id: user.id, kind: "expense")
  .where("tags @> ?::jsonb", [ tag ].to_json)

if ENV["DELETE"].present?
  rows = tagged.order(:date).to_a
  if rows.empty?
    puts "No hay gastos simulados con el tag #{tag.inspect}."
    exit
  end

  puts "Gastos simulados a borrar: #{rows.size}"
  puts "Rango: #{rows.first.date} .. #{rows.last.date}"
  puts "Total: #{money(rows.sum { |row| row.amount.to_d })}"

  if ENV["APPLY"].present?
    category_counts = rows.group_by(&:category_id).transform_values(&:size).compact
    source_counts = rows.group_by(&:money_source_id).transform_values(&:size).compact
    ActiveRecord::Base.transaction do
      deleted = tagged.delete_all
      adjust_counters(category_counts, source_counts, -1)
      puts "BORRADOS: #{deleted} gastos simulados."
    end
  else
    puts "Simulación: re-ejecuta con APPLY=1 DELETE=1 para borrar."
  end
  exit
end

if tagged.exists?
  abort "Ya existen gastos simulados con el tag #{tag.inspect}. Usa DELETE=1 para borrarlos primero."
end

source_expenses = Transaction.where(user_id: user.id, kind: "expense", date: current_cycle.to_range).order(:date)
abort "El ciclo actual (#{current_cycle.starts} .. #{current_cycle.ends}) no tiene gastos." if source_expenses.empty?

now = Time.current
rows = source_expenses.filter_map do |expense|
  new_date = expense.date << 1
  unless previous_cycle.to_range.cover?(new_date)
    abort "Fecha fuera del ciclo anterior: #{expense.date} -> #{new_date}"
  end
  if expense.money_source_id.blank?
    abort "El gasto #{expense.id} no tiene fuente de dinero."
  end

  {
    user_id: user.id,
    category_id: expense.category_id,
    money_source_id: expense.money_source_id,
    date: new_date,
    amount: (expense.amount.to_d * AMOUNT_FACTOR).round(2),
    kind: "expense",
    description: expense.description,
    source: "manual",
    recurring_template_id: nil,
    tags: [ tag ],
    created_at: now,
    updated_at: now
  }
end

total = rows.sum { |row| row[:amount] }
puts "Usuario: #{user.email} (ciclo inicia el día #{user.financial_cycle_start_day})"
puts "Ciclo actual:  #{current_cycle.starts} .. #{current_cycle.ends} (#{source_expenses.size} gastos)"
puts "Ciclo anterior: #{previous_cycle.starts} .. #{previous_cycle.ends}"
puts "Tag: #{tag}"
puts "Gastos a generar: #{rows.size} (30% menos cada uno)"
puts "Total simulado: #{money(total)}"
puts "Rango de fechas: #{rows.map { |row| row[:date] }.min} .. #{rows.map { |row| row[:date] }.max}"

by_category = rows.group_by { |row| row[:category_id] }.transform_values { |list| list.sum { |row| row[:amount] } }
puts
puts "Por categoría:"
Category.where(id: by_category.keys).order(:name).each do |category|
  puts "  #{category.name}: #{money(by_category[category.id])}"
end

if ENV["APPLY"].present?
  category_counts = rows.group_by { |row| row[:category_id] }.transform_values(&:size).except(nil)
  source_counts = rows.group_by { |row| row[:money_source_id] }.transform_values(&:size).except(nil)
  ActiveRecord::Base.transaction do
    Transaction.insert_all(rows)
    adjust_counters(category_counts, source_counts, 1)
  end
  puts
  puts "APLICADO: #{rows.size} gastos simulados insertados."
else
  puts
  puts "Simulación: re-ejecuta con APPLY=1 para insertar."
end
