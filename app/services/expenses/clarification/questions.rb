# frozen_string_literal: true

module Expenses
  module Clarification
    # Builds and delivers the Spanish clarification questions for a session's
    # pending candidates. Candidates are referenced by a stable 1..n numbering
    # (never internal IDs).
    #
    #   - One pending candidate: direct question; money source and category
    #     use an interactive WhatsApp list (tap = deterministic, no LLM).
    #   - One pending candidate: direct question; money source and category
    #     use an interactive WhatsApp list (tap = deterministic, no LLM).
    #   - Several pending candidates: ONE round at a time — the missing field
    #     shared by the most candidates is asked first with a numbered bullet
    #     list and an ordered-answer hint; follow-up rounds cover the rest
    #     (Resolver#follow_up rebuilds the question each turn from the
    #     remaining pending candidates). When the round — or the session —
    #     leaves a single pending candidate, its selectable fields use the
    #     interactive WhatsApp list again.
    module Questions
      FIELD_QUESTIONS = {
        "amount" => "¿Cuánto fue?",
        "date" => "¿De qué fecha fue?",
        "description" => "¿Qué fue?",
        "category_id" => "¿En qué categoría encaja?",
        "money_source_id" => "¿Con qué fuente de dinero se pagó?"
      }.freeze

      FIELD_LABELS = {
        "amount" => "el monto",
        "date" => "la fecha",
        "description" => "qué fue",
        "category_id" => "la categoría",
        "money_source_id" => "el medio de pago"
      }.freeze

      OTHER_ROW = { id: "other", title: "Otra (escribir)" }.freeze

      class << self
        # Ordered missing fields across all pending candidates: a field is
        # listed once, in the first candidate (by index) that misses it.
        def missing_fields(candidates)
          candidates.flat_map { |candidate| candidate.missing_fields }.uniq
        end

        # The candidate's first (lowest-index) missing field.
        def next_field(candidate)
          order = %w[amount date description category_id money_source_id]
          order.find { |field| candidate.missing_fields.include?(field) }
        end

        # Human label for a candidate in questions: description + amount.
        def candidate_label(candidate)
          label = candidate.description.presence || "Gasto"
          label += " — $#{format_amount(candidate.amount)}" if candidate.amount.present?
          label
        end

        # Question text for the session's pending candidates, numbered 1..n in
        # the same order the resolver receives them. A single candidate is
        # asked ONE field at a time (each selectable field gets its own
        # interactive list on its own turn). Several candidates are asked one
        # ROUND at a time: only the round's candidates (largest shared
        # missing-field group) are listed in the question text.
        def build_text(pending_candidates)
          if pending_candidates.size == 1
            direct_question(pending_candidates.first)
          else
            grouped_question(round_candidates(pending_candidates))
          end
        end

        # Candidates participating in the current round: all pending
        # candidates missing the field shared by the largest group (ties go
        # to the earliest field in the canonical order). The question — and
        # the numbering the LLM resolver sees — covers only these; the rest
        # stay pending in the session for later rounds.
        def round_candidates(pending_candidates)
          candidates = pending_candidates.to_a
          field = round_field(candidates)
          candidates.select { |candidate| candidate.missing_fields.include?(field) }
        end

        # The missing field shared by the most candidates; ties break to the
        # earliest position in the fixed field order.
        def round_field(candidates)
          order = %w[amount date description category_id money_source_id]
          field_counts = candidates.flat_map { |candidate| candidate.missing_fields }
                                   .tally
          order.select { |field| field_counts.key?(field) }
               .max_by { |field| field_counts.fetch(field, 0) }
        end

        # Delivers the question for the session: for a single pending
        # candidate the FIRST missing field is asked, with its interactive
        # list when selectable; several pending candidates get the round
        # text (largest shared missing-field group, plain text).
        # When the interactive list cannot be delivered (Meta API failure,
        # payload rejection) the question still reaches the user as plain
        # text — a clarification never dies in silence.
        # Returns the delivered question text for persistence.
        def deliver(session)
          pending = session.pending_candidates.to_a
          text = build_text(pending)

          delivered = false
          if pending.size == 1
            field = round_field(pending)
            delivered = send_source_list(session.phone_number, pending.first, text) if field == "money_source_id"
            delivered = send_category_list(session.phone_number, pending.first, text) if field == "category_id"
          end
          Whatsapp::ReplySender.send_to(session.phone_number, text) unless delivered

          text
        end

        private

        def direct_question(candidate)
          field = next_field(candidate)
          "#{expense_context(candidate)} #{FIELD_QUESTIONS.fetch(field, 'Me falta información.')}"
        end

        # One grouped question per round: every listed candidate misses the
        # SAME field, so the question asks that one thing for all of them and
        # shows the ordered-answer hint (plus a "todos con X" shortcut).
        def grouped_question(pending_candidates)
          field = round_field(pending_candidates)
          lines = pending_candidates.each_with_index.map do |candidate, index|
            "#{index + 1}. #{candidate_label(candidate)}"
          end
          example = ordered_example(pending_candidates, field)
          <<~MSG.strip
            Me falta #{FIELD_LABELS.fetch(field, field)} de estos gastos:

            #{lines.join("\n")}

            #{FIELD_QUESTIONS.fetch(field, 'Me falta información.')}
            Puedes responder en el mismo orden, por ejemplo: "#{example}", o algo como "todos con efectivo".
          MSG
        end

        def ordered_example(pending_candidates, field)
          if field == "money_source_id"
            "tarjeta, efectivo, tarjeta".split(", ").first(pending_candidates.size).join(", ")
          elsif field == "category_id"
            Array.new(pending_candidates.size, "transporte").join(", ")
          else
            "dato1, dato2, dato3".split(", ").first(pending_candidates.size).join(", ")
          end
        end

        def expense_context(candidate)
          what = candidate.description.presence || "Tu gasto"
          parts = [ "\"#{what}\"" ]
          parts << "de $#{format_amount(candidate.amount)}" if candidate.amount.present?
          parts << "del #{candidate.date.strftime('%d/%m/%Y')}" if candidate.date.present?
          "Registré #{parts.join(' ')}."
        end

        def format_amount(amount)
          ActionController::Base.helpers.number_to_currency(amount, unit: "", delimiter: ".", separator: ",",
                                                            precision: 0)
        end

        def send_source_list(phone_number, candidate, text)
          sources = candidate.user.money_sources.active.payment_sources.order(:kind, :name).to_a
          return false if sources.empty?

          rows = sources.first(9).map { |source| { id: "source:#{source.id}", title: source.display_name } }
          Whatsapp::ReplySender.send_list(phone_number, text, rows + [ OTHER_ROW ])
        end

        def send_category_list(phone_number, candidate, text)
          rows = category_rows(candidate)
          return false if rows.empty?

          Whatsapp::ReplySender.send_list(phone_number, text, rows + [ OTHER_ROW ])
        end

        # The candidate's AI suggestion first (if any), then the user's most
        # frequently used expense categories; with no usage history the
        # available expense categories fill the list.
        def category_rows(candidate)
          user = candidate.user
          rows = []

          suggestion = candidate.category_suggestion.presence
          if suggestion
            suggested = Categories::ClosestResolver.call(user: user, name: suggestion).category
            rows << { id: "category:#{suggested.id}", title: suggested.name } if suggested
          end

          category_ids = user.expenses.where.not(category_id: nil)
                             .group(:category_id)
                             .order(Arel.sql("COUNT(category_id) DESC"))
                             .limit(suggestion ? 8 : 9).pluck(:category_id)
          if category_ids.empty?
            category_ids = Category.for_user(user).expenses.limit(9).pluck(:id)
          end
          categories = Category.expenses.where(id: category_ids).index_by(&:id)
          rows += category_ids.filter_map { |id| { id: "category:#{id}", title: categories[id].name } if categories[id] }

          rows.uniq { |row| row[:id] }
        end
      end
    end
  end
end
