# frozen_string_literal: true

module FinancialHabits
  # FinancialHabits::Detail
  # Builds the data for the "Ver análisis" screen. It reuses the deterministic
  # analysis and only queries the movements needed for the selected habit.
  class Detail
    LAST_DAYS = 5
    SLOTS = SpendingTimePatternAnalyzer::SLOTS

    attr_reader :user, :key, :date

    def initialize(user:, key:, date: Date.current)
      @user = user
      @key = key.to_s
      @date = date.to_date
    end

    def call
      analysis = Analysis.new(user: user, date: date).call
      @range = analysis[:period]
      discovery = analysis[:discoveries].find { |item| item[:key].to_s == key }

      return { state: :not_found, analysis: analysis, discovery: nil, detail: nil } unless discovery

      {
        state: :ok,
        analysis: analysis,
        discovery: discovery,
        detail: build_detail(discovery)
      }
    end

    private

    def build_detail(discovery)
      case key
      when "income_spending_pattern" then income_detail(discovery)
      when "spending_time_pattern" then time_detail(discovery)
      when "spending_weekday_pattern" then weekday_detail(discovery)
      when "merchant_frequency" then merchant_detail(discovery)
      when "credit_usage_pattern" then credit_detail(discovery)
      when "cycle_end_spending" then cycle_end_detail(discovery)
      when "behavior_change" then behavior_change_detail(discovery)
      when "planning_opportunity" then planning_detail(discovery)
      else generic_detail(discovery)
      end
    end

    # --- income -------------------------------------------------------------

    def income_detail(discovery)
      income_rows = incomes.sort_by(&:date)
      buckets = { "Días 1–5" => 0.to_d, "Días 6–10" => 0.to_d, "Días 11–20" => 0.to_d, "Resto del ciclo" => 0.to_d }
      classified = expenses.filter_map do |expense|
        income = income_rows.select { |row| row.date <= expense.date }.max_by(&:date)
        next unless income

        days = (expense.date - income.date).to_i + 1
        bucket = if days <= 5
          "Días 1–5"
        elsif days <= 10
          "Días 6–10"
        elsif days <= 20
          "Días 11–20"
        else
          "Resto del ciclo"
        end
        amount = expense.amount.to_d.abs
        buckets[bucket] += amount
        { expense: expense, income: income, days: days, bucket: bucket, amount: amount }
      end

      total = buckets.values.sum
      first_five = classified.select { |row| row[:days] <= 5 }
      first_five_total = first_five.sum { |row| row[:amount] }
      pct = total.positive? ? (first_five_total / total * 100).round : 0

      cycles = income_rows.each_with_index.filter_map do |income, index|
        next_income = income_rows[index + 1]
        cycle_rows = classified.select { |row| row[:income] == income }
        next if cycle_rows.empty?

        cycle_total = cycle_rows.sum { |row| row[:amount] }
        cycle_first = cycle_rows.select { |row| row[:days] <= 5 }.sum { |row| row[:amount] }
        {
          label: I18n.l(income.date, format: "%B %Y"),
          value: cycle_first.round(2),
          pct: cycle_total.positive? ? (cycle_first / cycle_total * 100).round : 0,
          detail: next_income ? "Ciclo hasta #{I18n.l(next_income.date - 1.day, format: '%-d %b')}" : "Ciclo en curso"
        }
      end

      {
        primary: { value: "#{pct}%", label: "de tus gastos", caption: "ocurrieron durante los primeros #{LAST_DAYS} días después de recibir ingresos." },
        visualization: {
          type: "bars",
          title: "¿Cuándo gastas más?",
          rows: buckets.map do |label, value|
            { label: label, value: value.round(2), pct: total.positive? ? (value / total * 100).round : 0, highlight: label == "Días 1–5" }
          end
        },
        evolution: { title: "Así se ha repetido en el tiempo", rows: cycles },
        breakdown: { title: "¿En qué se concentraron esos gastos?", rows: category_rows(first_five.map { |row| row[:expense] }) },
        interpretation: interpretation_for(discovery, cycles, pct),
        recommendation: discovery[:recommendation],
        related_movements: movements(first_five.map { |row| row[:expense] }),
        summary_rows: [
          { label: "Gasto en primeros 5 días", value: first_five_total.round(2), money: true },
          { label: "Resto del ciclo", value: (total - first_five_total).round(2), money: true },
          { label: "Ciclos observados", value: cycles.size },
          { label: "Ingresos identificados", value: income_rows.size }
        ]
      }
    end

    # --- time ---------------------------------------------------------------

    def time_detail(discovery)
      timed = expenses.select { |expense| reliable_time(expense).present? }
      slot_rows = SLOTS.map do |slot|
        items = timed.select { |expense| slot[:range].cover?(reliable_time(expense).hour) }
        { label: slot[:label], count: items.size, value: items.sum { |expense| expense.amount.to_d.abs }.round(2) }
      end
      total_count = timed.size
      total_value = timed.sum { |expense| expense.amount.to_d.abs }
      peak = slot_rows.max_by { |row| row[:count] }
      peak_slot = SLOTS.find { |slot| slot[:label] == peak[:label] }
      peak_items = timed.select { |expense| peak_slot[:range].cover?(reliable_time(expense).hour) }

      evolution = expenses.group_by { |expense| expense.date.beginning_of_month }.sort.map do |month, items|
        month_timed = items.select { |expense| reliable_time(expense).present? }
        next if month_timed.empty?

        row = SLOTS.map do |slot|
          count = month_timed.count { |expense| slot[:range].cover?(reliable_time(expense).hour) }
          [ slot[:label], count ]
        end.max_by { |_label, count| count }
        { label: I18n.l(month, format: "%B %Y"), value: row[0], pct: month_timed.size.positive? ? (row[1].to_f / month_timed.size * 100).round : 0 }
      end.compact

      {
        primary: { value: peak[:label].to_s.capitalize, label: "franja con más actividad", caption: "#{peak[:count]} compras · #{total_count.positive? ? (peak[:count].to_f / total_count * 100).round : 0}% del total." },
        visualization: {
          type: "bars",
          title: "Actividad por franja horaria",
          rows: slot_rows.map do |row|
            { label: row[:label], value: row[:value], pct: total_count.positive? ? (row[:count].to_f / total_count * 100).round : 0, count: row[:count], highlight: row[:label] == peak[:label] }
          end
        },
        evolution: { title: "Franja predominante por mes", rows: evolution },
        breakdown: { title: "¿Qué compras predominan en esa franja?", rows: category_rows(peak_items) },
        interpretation: "Una parte importante de tus compras ocurre en la franja de #{peak[:label]}. Este comportamiento puede estar relacionado con tus rutinas de alimentación, actividades personales o compras realizadas al finalizar el día. No implica por sí solo que sean compras impulsivas.",
        recommendation: discovery[:recommendation],
        related_movements: movements(peak_items),
        summary_rows: [
          { label: "Compras en la franja", value: peak[:count] },
          { label: "Valor en la franja", value: peak[:value], money: true },
          { label: "Promedio por compra", value: peak[:count].positive? ? (peak[:value] / peak[:count]).round(2) : 0, money: true },
          { label: "Movimientos con hora", value: total_count }
        ]
      }
    end

    # --- weekday ------------------------------------------------------------

    def weekday_detail(discovery)
      names = { 1 => "Lunes", 2 => "Martes", 3 => "Miércoles", 4 => "Jueves", 5 => "Viernes", 6 => "Sábado", 0 => "Domingo" }
      rows = [ 1, 2, 3, 4, 5, 6, 0 ].map do |wday|
        items = expenses.select { |expense| expense.date.wday == wday }
        {
          label: names[wday],
          wday: wday,
          count: items.size,
          value: items.sum { |expense| expense.amount.to_d.abs }.round(2),
          average: items.size.positive? ? (items.sum { |expense| expense.amount.to_d.abs } / items.size).round(2) : 0
        }
      end
      peak_count = rows.max_by { |row| row[:count] }
      peak_value = rows.max_by { |row| row[:value] }
      peak_items = expenses.select { |expense| expense.date.wday == peak_count[:wday] }
      total_count = expenses.size
      pct = total_count.positive? ? (peak_count[:count].to_f / total_count * 100).round : 0

      {
        primary: { value: peak_count[:label], label: "día con más transacciones", caption: "#{peak_count[:count]} movimientos · #{pct}% del total." },
        visualization: {
          type: "bars",
          title: "Gasto por día de la semana",
          rows: rows.map { |row| { label: row[:label], value: row[:value], pct: total_count.positive? ? (row[:count].to_f / total_count * 100).round : 0, count: row[:count], highlight: row[:label] == peak_count[:label] } }
        },
        evolution: { title: "Promedio por día", rows: rows.map { |row| { label: row[:label], value: row[:average], money: true, pct: nil } } },
        breakdown: { title: "¿Qué categorías explican ese día?", rows: category_rows(peak_items) },
        interpretation: "El día con más transacciones es #{peak_count[:label].downcase}, mientras que el mayor valor gastado se concentra en #{peak_value[:label].downcase}. Pueden ser días distintos y no representan un problema por sí mismos.",
        recommendation: discovery[:recommendation],
        related_movements: movements(peak_items),
        summary_rows: [
          { label: "Día con más transacciones", value: peak_count[:label] },
          { label: "Día con mayor gasto", value: peak_value[:label] },
          { label: "Participación del día principal", value: "#{pct}%" },
          { label: "Semanas observadas", value: (expenses.map { |expense| expense.date.beginning_of_week }.uniq.size) }
        ]
      }
    end

    # --- merchants ----------------------------------------------------------

    def merchant_detail(discovery)
      groups = expenses.group_by { |expense| normalize(expense.description) }
      merchants = groups.filter_map do |group_key, group|
        next if group_key.blank?

        dates = group.map(&:date).uniq.sort
        next if dates.size < 2 || group.size < MerchantFrequencyAnalyzer::MIN_VISITS

        intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }
        total = group.sum { |expense| expense.amount.to_d.abs }
        {
          key: group_key,
          name: group.first.description.to_s.strip.presence || group_key,
          visits: group.size,
          total: total.round(2),
          average: (total / group.size).round(2),
          interval: intervals.any? ? (intervals.sum.to_f / intervals.size).round : nil,
          group: group
        }
      end.sort_by { |merchant| -merchant[:visits] }

      top = merchants.first
      return generic_detail(discovery) unless top

      evolution = top[:group].group_by { |expense| expense.date.beginning_of_month }.sort.map do |month, items|
        { label: I18n.l(month, format: "%B %Y"), value: items.size, pct: nil }
      end

      {
        primary: { value: "#{merchants.size} lugares", label: "con visitas recurrentes", caption: "#{top[:name]} es el más frecuente con #{top[:visits]} visitas." },
        visualization: {
          type: "ranking",
          title: "Establecimientos recurrentes",
          rows: merchants.first(8).map do |merchant|
            { label: merchant[:name], value: merchant[:total], visits: merchant[:visits], average: merchant[:average], interval: merchant[:interval], highlight: merchant == top }
          end
        },
        evolution: { title: "Visitas por mes · #{top[:name]}", rows: evolution },
        breakdown: { title: "Categorías asociadas", rows: category_rows(top[:group]) },
        interpretation: "#{top[:name]} aparece entre tus movimientos con bastante frecuencia. En el periodo analizado registraste #{top[:visits]} visitas, lo que indica que forma parte de tu rutina de compras.",
        recommendation: discovery[:recommendation],
        expenses_link: expenses_link(query: top[:name], category_id: top_category(top[:group]), start_date: range.begin, end_date: range.end),
        related_movements: movements(top[:group]),
        summary_rows: [
          { label: "Establecimientos recurrentes", value: merchants.size },
          { label: "Visitas totales", value: merchants.sum { |merchant| merchant[:visits] } },
          { label: "Valor acumulado", value: merchants.sum { |merchant| merchant[:total] }.round(2), money: true },
          { label: "Frecuencia promedio", value: "#{merchants.sum { |merchant| merchant[:visits] }.to_f / merchants.size} visitas" }
        ]
      }
    end

    # --- credit -------------------------------------------------------------

    def credit_detail(discovery)
      credit = expenses.select { |expense| expense.money_source&.credit_card? }
      other = expenses.reject { |expense| expense.money_source&.credit_card? }
      credit_total = credit.sum { |expense| expense.amount.to_d.abs }
      other_total = other.sum { |expense| expense.amount.to_d.abs }
      total = credit_total + other_total
      pct = total.positive? ? (credit_total / total * 100).round : 0

      evolution = expenses.group_by { |expense| expense.date.beginning_of_month }.sort.map do |month, items|
        month_credit = items.select { |expense| expense.money_source&.credit_card? }
        month_total = items.sum { |expense| expense.amount.to_d.abs }
        { label: I18n.l(month, format: "%B %Y"), value: month_total.positive? ? (month_credit.sum { |expense| expense.amount.to_d.abs } / month_total * 100).round : 0, pct: nil }
      end

      {
        primary: { value: "#{pct}%", label: "de tus gastos cotidianos", caption: "se pagó con tarjeta de crédito en el periodo." },
        visualization: {
          type: "comparison",
          title: "Crédito vs. otros medios",
          rows: [
            { label: "Tarjeta de crédito", value: credit_total.round(2), pct: pct, highlight: true },
            { label: "Otros medios", value: other_total.round(2), pct: 100 - pct }
          ]
        },
        evolution: { title: "Participación del crédito por mes", rows: evolution },
        breakdown: { title: "¿Dónde se concentra el crédito?", rows: category_rows(credit) },
        interpretation: "Durante el periodo analizado usaste tu tarjeta de crédito para cubrir una parte de tus gastos cotidianos. La participación del crédito #{evolution.size >= 2 && evolution.last[:value] > evolution.first[:value] ? 'aumentó' : 'se mantuvo'} en el periodo. Esto no permite concluir que estés endeudándote más.",
        recommendation: discovery[:recommendation],
        expenses_link: expenses_link(money_source_id: credit.first&.money_source_id, category_id: top_category(credit), start_date: range.begin, end_date: range.end),
        related_movements: movements(credit),
        summary_rows: [
          { label: "Consumos con crédito", value: credit_total.round(2), money: true },
          { label: "Otros medios", value: other_total.round(2), money: true },
          { label: "Transacciones con crédito", value: credit.size },
          { label: "Participación", value: "#{pct}%" }
        ]
      }
    end

    # --- cycle end ----------------------------------------------------------

    def cycle_end_detail(discovery)
      income_rows = incomes.sort_by(&:date)
      cycles = income_rows.each_with_index.filter_map do |income, index|
        next_income = income_rows[index + 1]
        next unless next_income

        cycle_start = income.date
        cycle_end = next_income.date - 1.day
        items = expenses.select { |expense| expense.date.between?(cycle_start, cycle_end) }
        next if items.empty?

        total = items.sum { |expense| expense.amount.to_d.abs }
        last_items = items.select { |expense| expense.date.between?(cycle_end - (LAST_DAYS - 1), cycle_end) }
        last_total = last_items.sum { |expense| expense.amount.to_d.abs }
        {
          start_date: cycle_start,
          end_date: cycle_end,
          total: total,
          last_items: last_items,
          last_total: last_total,
          pct: total.positive? ? (last_total / total * 100).round : 0
        }
      end

      all_items = cycles.flat_map { |cycle| cycle[:last_items] }
      all_total = cycles.sum { |cycle| cycle[:total] }
      last_total = cycles.sum { |cycle| cycle[:last_total] }
      pct = all_total.positive? ? (last_total / all_total * 100).round : 0

      {
        primary: { value: "#{pct}%", label: "de tus gastos", caption: "ocurrieron en los últimos #{LAST_DAYS} días de tus ciclos completos." },
        visualization: {
          type: "bars",
          title: "Distribución dentro del ciclo",
          rows: cycle_distribution_rows(cycles),
          note: "Los últimos días del ciclo se destacan para comparar el cierre con el resto del periodo."
        },
        evolution: { title: "Cierre de cada ciclo", rows: cycles.map { |cycle| { label: I18n.l(cycle[:start_date], format: "%B %Y"), value: cycle[:last_total].round(2), pct: cycle[:pct] } } },
        breakdown: { title: "Gastos de cierre por categoría", rows: category_rows(all_items) },
        interpretation: "En los ciclos completos analizados se observa una concentración de gastos durante los cinco días anteriores a recibir nuevos ingresos. Esto puede estar relacionado con compras habituales, obligaciones pendientes o gastos que se acumulan al finalizar el periodo. No permite concluir que te estés quedando sin dinero.",
        recommendation: discovery[:recommendation],
        related_movements: movements(all_items),
        summary_rows: [
          { label: "Ciclos completos", value: cycles.size },
          { label: "Gastos últimos 5 días", value: last_total.round(2), money: true },
          { label: "Resto de los ciclos", value: (all_total - last_total).round(2), money: true },
          { label: "Promedio diario de cierre", value: cycles.size.positive? ? (last_total / (cycles.size * LAST_DAYS)).round(2) : 0, money: true }
        ]
      }
    end

    # --- behavior change ----------------------------------------------------

    def behavior_change_detail(discovery)
      by_month = expenses.group_by { |expense| expense.date.beginning_of_month }.sort
      return generic_detail(discovery) if by_month.size < 2

      current_month, current_items = by_month.last
      historical = by_month[0...-1]
      historical_average = historical.sum { |_month, items| items.sum { |expense| expense.amount.to_d.abs } } / historical.size
      current_total = current_items.sum { |expense| expense.amount.to_d.abs }
      delta = historical_average.positive? ? ((current_total - historical_average) / historical_average * 100).round : 0

      {
        primary: { value: "#{delta.positive? ? '+' : ''}#{delta}%", label: "frente a tu promedio habitual", caption: "en #{I18n.l(current_month, format: '%B %Y')}." },
        visualization: {
          type: "bars",
          title: "Gasto por mes",
          rows: by_month.map do |month, items|
            total = items.sum { |expense| expense.amount.to_d.abs }
            { label: I18n.l(month, format: "%B %Y"), value: total.round(2), pct: historical_average.positive? ? (total / historical_average * 100).round : 0, highlight: month == current_month }
          end
        },
        evolution: { title: "Evolución mensual", rows: by_month.map { |month, items| { label: I18n.l(month, format: "%B %Y"), value: items.sum { |expense| expense.amount.to_d.abs }.round(2), money: true } } },
        breakdown: { title: "Categorías del mes actual", rows: category_rows(current_items) },
        interpretation: "Tus gastos del mes actual se comparan con el promedio de los meses anteriores. Un cambio de comportamiento puede ser temporal o convertirse en una nueva rutina; conviene revisar qué categorías explican la diferencia.",
        recommendation: discovery[:recommendation],
        expenses_link: expenses_link(category_id: top_category(current_items), start_date: current_month.begin, end_date: [ current_month.end, range.end ].min),
        related_movements: movements(current_items),
        summary_rows: [
          { label: "Mes actual", value: current_total.round(2), money: true },
          { label: "Promedio histórico", value: historical_average.round(2), money: true },
          { label: "Variación", value: "#{delta.positive? ? '+' : ''}#{delta}%" },
          { label: "Meses comparados", value: by_month.size }
        ]
      }
    end

    # --- planning -----------------------------------------------------------

    def planning_detail(discovery)
      groups = expenses.group_by { |expense| normalize(expense.description) }
      patterns = groups.filter_map do |group_key, group|
        next if group_key.blank?

        dates = group.map(&:date).uniq.sort
        next if dates.size < 3

        amounts = group.map { |expense| expense.amount.to_d.abs }
        median_amount = median(amounts)
        next unless median_amount.positive?

        spread = (amounts.max - amounts.min) / median_amount
        next if spread > 0.25

        intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }
        interval = median(intervals)
        next unless interval.between?(25, 40)

        { key: group_key, name: group.first.description.to_s.strip.presence || group_key, group: group, interval: interval, amount: median_amount }
      end.sort_by { |pattern| -pattern[:group].size }

      top = patterns.first
      return generic_detail(discovery) unless top

      evolution = top[:group].group_by { |expense| expense.date.beginning_of_month }.sort.map do |month, items|
        { label: I18n.l(month, format: "%B %Y"), value: items.sum { |expense| expense.amount.to_d.abs }.round(2), money: true }
      end

      {
        primary: { value: "#{patterns.size} gastos", label: "podrías anticipar", caption: "#{top[:name]} se repite aproximadamente cada #{top[:interval]} días." },
        visualization: {
          type: "ranking",
          title: "Pagos con cierta regularidad",
          rows: patterns.first(8).map do |pattern|
            { label: pattern[:name], value: pattern[:amount], visits: pattern[:group].size, interval: pattern[:interval], highlight: pattern == top }
          end
        },
        evolution: { title: "Evolución de #{top[:name]}", rows: evolution },
        breakdown: { title: "Categorías asociadas", rows: category_rows(top[:group]) },
        interpretation: "Estos pagos se repiten con una regularidad aproximada. Identificarlos te permite planificar su monto y fecha en lugar de tratarlos como gastos inesperados.",
        recommendation: discovery[:recommendation],
        expenses_link: expenses_link(query: top[:name], category_id: top_category(top[:group]), start_date: range.begin, end_date: range.end),
        related_movements: movements(top[:group]),
        summary_rows: [
          { label: "Pagos regulares", value: patterns.size },
          { label: "Patrón principal", value: top[:name] },
          { label: "Intervalo aproximado", value: "#{top[:interval]} días" },
          { label: "Monto habitual", value: top[:amount].round(2), money: true }
        ]
      }
    end

    # --- generic ------------------------------------------------------------

    def generic_detail(discovery)
      {
        primary: { value: "—", label: "análisis", caption: discovery[:description] },
        visualization: { type: "bars", title: "Datos del análisis", rows: [] },
        evolution: { title: "Evolución", rows: [] },
        breakdown: { title: "Desglose", rows: [] },
        interpretation: discovery[:description],
        recommendation: discovery[:recommendation],
        related_movements: movements(expenses),
        summary_rows: []
      }
    end

    # --- helpers ------------------------------------------------------------

    def expenses_link(query: nil, money_source_id: nil, category_id: nil, start_date: nil, end_date: nil)
      params = { q: query, money_source_id: money_source_id, category_id: category_id,
                 start_date: start_date&.to_s, end_date: end_date&.to_s }.compact
      Rails.application.routes.url_helpers.expenses_path(params)
    end

    def top_category(items)
      top = category_rows(items).first
      top[:id] if top && top[:pct].to_i >= 20
    end

    def expenses
      @expenses ||= Expense.for_user(user)
                           .where(date: range)
                           .where.missing(:payments)
                           .where(gmf_origin_type: nil)
                           .includes(:money_source, :category)
                           .order(date: :asc, created_at: :asc)
                           .to_a
    end

    def incomes
      @incomes ||= Income.for_user(user).where(date: range).to_a
    end

    def range
      @range ||= Analysis.new(user: user, date: date).call[:period]
    end

    def category_rows(items)
      total = items.sum { |expense| expense.amount.to_d.abs }
      items.group_by { |expense| expense.category&.name || "Sin categoría" }
           .map do |name, group|
        value = group.sum { |expense| expense.amount.to_d.abs }
        { id: group.first&.category_id, label: name, value: value.round(2), pct: total.positive? ? (value / total * 100).round : 0, count: group.size }
      end.sort_by { |row| -row[:value] }
    end

    def movements(items)
      items.first(12).map do |expense|
        {
          id: expense.id,
          date: expense.date,
          description: expense.description.to_s,
          amount: expense.amount.to_d.abs.round(2),
          category: expense.category&.name || "Sin categoría",
          money_source: expense.money_source&.name
        }
      end
    end

    def cycle_distribution_rows(cycles)
      buckets = { "Primeros 5 días" => 0.to_d, "Parte media" => 0.to_d, "Últimos 6–10 días" => 0.to_d, "Últimos 5 días" => 0.to_d }
      cycles.each do |cycle|
        expenses.select { |expense| expense.date.between?(cycle[:start_date], cycle[:end_date]) }.each do |expense|
          from_start = (expense.date - cycle[:start_date]).to_i + 1
          from_end = (cycle[:end_date] - expense.date).to_i + 1
          bucket = if from_end <= LAST_DAYS
            "Últimos 5 días"
          elsif from_end <= 10
            "Últimos 6–10 días"
          elsif from_start <= 5
            "Primeros 5 días"
          else
            "Parte media"
          end
          buckets[bucket] += expense.amount.to_d.abs
        end
      end
      total = buckets.values.sum
      buckets.map { |label, value| { label: label, value: value.round(2), pct: total.positive? ? (value / total * 100).round : 0, highlight: label == "Últimos 5 días" } }
    end

    def interpretation_for(discovery, cycles, pct)
      if cycles.size >= 2
        "En los #{cycles.size} ciclos analizados, tus gastos se concentraron #{pct >= 50 ? 'especialmente' : 'en buena medida'} durante los primeros cinco días después de recibir ingresos. Esto puede estar relacionado con el pago de obligaciones, compras planificadas o una mayor disponibilidad de dinero al inicio del ciclo. Por sí solo, no significa que estés gastando de más."
      else
        "Detectamos una señal inicial: una parte de tus gastos se concentra en los primeros días después de recibir ingresos. Necesitamos más ciclos para confirmar si es un hábito recurrente."
      end
    end

    def reliable_time(expense)
      if expense.respond_to?(:occurred_at) && expense.occurred_at.is_a?(Time)
        expense.occurred_at
      elsif expense.respond_to?(:created_at) && expense.created_at.present? &&
            expense.created_at.to_date == expense.date
        expense.created_at
      end
    end

    def normalize(description)
      text = ActiveSupport::Inflector.transliterate(description.to_s).downcase
      text = text.gsub(%r{\b\d{1,2}[/.-]\d{1,2}([/.-]\d{2,4})?\b}, " ")
      text = text.gsub(/\b\d{3,}\b/, " ")
      text = text.gsub(/[^a-z0-9\s]/, " ")
      text.split.reject { |word| word.match?(/\A\d+\z/) }.join(" ").squeeze(" ").strip
    end

    def median(values)
      sorted = values.sort
      sorted[sorted.size / 2]
    end
  end
end