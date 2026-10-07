# frozen_string_literal: true

module Expenses
  module Clarification
    # Drives the conversational clarification flow for the incomplete expense
    # candidates of a WhatsApp message. The flow is ARRAY-based end to end:
    # a session groups every incomplete candidate of the original message,
    # questions are grouped (never one message per expense) and the LLM
    # resolver returns one resolution entry per matched candidate.
    #
    #   start_session! — persists the session grouping the candidates and
    #                    delivers the first (grouped) question
    #   handle_reply   — interprets a free-text answer (LLM, array in/out)
    #   handle_tap     — resolves a deterministic interactive list tap (no
    #                    LLM; only when a single candidate is pending)
    #
    # Only missing fields are ever applied; existing candidate data is
    # preserved. Each candidate that becomes complete is converted with the
    # existing ExpenseCandidate#confirm! immediately (no waiting for the
    # rest, no duplicated creation logic). Follow-ups are capped to avoid
    # infinite loops; past the cap the session is abandoned and remaining
    # candidates stay needs_review.
    module Resolver
      module_function

      # Creates the pending session for the incomplete candidates (when none
      # exists) and delivers the first grouped question. Returns the session
      # or nil when nothing is missing or a session is already open.
      def start_session!(user:, phone_number:, candidates:, original_message: nil)
        incomplete = candidates.select { |candidate| candidate.missing_fields.present? }
        return nil if incomplete.empty?
        return nil if user.expense_clarifications.pending.exists?

        session = user.expense_clarifications.create!(
          phone_number: phone_number,
          original_message: original_message
        )
        incomplete.each do |candidate|
          session.expense_clarification_candidates.create!(
            expense_candidate: candidate,
            missing_fields: candidate.missing_fields
          )
        end
        session.update!(question: Questions.deliver(session), questions_count: 1)
        Rails.logger.info "[Clarification::Resolver] Session=#{session.id} started for user=#{user.id} " \
                          "with #{incomplete.size} candidate(s): " \
                          "#{incomplete.map { |c| "#{c.description} mf=#{c.missing_fields.inspect}" }.join(' | ')}"
        session
      end

      # Free-text answer to the pending clarification. Returns
      # [outcome_symbol, new_expense_fragment] where the fragment is the
      # exact text of a brand-new expense detected in the reply (nil when the
      # reply was purely a clarification). The caller runs the fragment
      # through the normal pipeline; the session stays pending meanwhile.
      def handle_reply(clarification:, reply_text:)
        clarification.with_lock do
          return [ :stale, nil ] unless clarification.pending?
          # A session whose candidates were all resolved outside the
          # conversation (web confirmation, pipeline) is a zombie: heal it by
          # closing and let the caller treat the reply as a normal message.
          if clarification.all_candidates_resolved?
            clarification.close!(:resolved)
            return [ :stale, nil ]
          end

          Rails.logger.info "[Clarification::Resolver] Reply for session=#{clarification.id}: " \
                            "#{reply_text.to_s.strip[0, 80].inspect} " \
                            "(pending=#{clarification.pending_candidates.count})"

          # A pending category proposal short-circuits the LLM: a textual
          # confirmation behaves exactly like the "Sí, crear" button tap;
          # any other reply discards the proposal and is resolved normally.
          if clarification.pending_category_name.present?
            if confirms?(reply_text)
              return [ apply_new_category(clarification), nil ]
            end
            discard_pending_category(clarification)
          end

          result = Ai::Router.call(
            task: :clarification_resolution,
            input: reply_text,
            context: {
              user: clarification.user,
              candidates: candidates_context(clarification),
              question: clarification.question,
              original_message: clarification.original_message,
              categories: Category.for_user(clarification.user).expenses.pluck(:name),
              money_source_identifiers: money_source_identifiers(clarification.user),
              today: Date.current
            }
          )

          unless result.ok?
            Whatsapp::ReplySender.send_to(clarification.phone_number,
                                          "No pude procesar tu respuesta, inténtalo de nuevo 🙏")
            return [ :llm_error, nil ]
          end

          data = result.data
          Rails.logger.info "[Clarification::Resolver] LLM result for session=#{clarification.id}: " \
                            "resolutions=#{Array(data[:resolutions]).inspect[0, 200]} " \
                            "new_category=#{data[:new_category_name].inspect} " \
                            "new_expense=#{data[:new_expense_text].inspect}"

          # The user clearly named a category that does not exist: propose it
          # with Sí/No buttons instead of creating it right away. This turn
          # does not consume the follow-up limit (same as the "other" tap).
          if data[:new_category_name].present?
            propose_category(clarification, data[:new_category_name])
            return [ :category_proposed, nil ]
          end

          new_expense_text = data[:new_expense_text].presence
          applied = apply_resolutions!(clarification, data[:resolutions] || [])
          Rails.logger.info "[Clarification::Resolver] Applied #{applied} resolution(s) for " \
                            "session=#{clarification.id}; pending=#{clarification.pending_candidates.count}"

          if clarification.all_candidates_resolved?
            complete_session!(clarification)
            outcome = :completed
          elsif applied.positive?
            outcome = follow_up(clarification)
          elsif new_expense_text.blank?
            outcome = follow_up(clarification, "No entendí cuál gasto estás aclarando. " +
                                               Questions.build_text(clarification.pending_candidates))
          end

          [ outcome, new_expense_text ]
        end
      rescue StandardError => e
        Rails.logger.error("[Clarification::Resolver] reply failed: #{e.message}")
        Whatsapp::ReplySender.send_to(clarification.phone_number,
                                      "Tuve un problema procesando tu respuesta, inténtalo de nuevo 🙏")
        [ :error, nil ]
      end

      # Deterministic resolution of a tapped list/button row:
      # "source:<id>", "category:<id>", "other" (asks the user to write it
      # instead; this navigation does not count against the follow-up limit)
      # and the new-category confirmation taps "newcategory:yes"/"no".
      def handle_tap(clarification:, interactive_reply:)
        clarification.with_lock do
          return :stale unless clarification.pending?

          pending = clarification.pending_candidates.to_a
          return :stale if pending.empty?

          candidate = pending.first
          row_id = interactive_reply["id"].to_s
          Rails.logger.info "[Clarification::Resolver] Tap for session=#{clarification.id}: #{row_id}"

          case row_id
          when "newcategory:yes"
            return :tap_ignored if clarification.pending_category_name.blank?

            return apply_new_category(clarification)
          when "newcategory:no"
            return :tap_ignored if clarification.pending_category_name.blank?

            discard_pending_category(clarification)
            return follow_up(clarification)
          when /\Asource:(\d+)\z/
            source = clarification.user.money_sources.active.payment_sources.find_by(id: ::Regexp.last_match(1))
            return :tap_ignored unless source

            candidate.update!(money_source_id: source.id)
          when /\Acategory:(\d+)\z/
            category = Category.for_user(clarification.user).expenses.find_by(id: ::Regexp.last_match(1))
            return :tap_ignored unless category

            candidate.update!(category_id: category.id)
          else
            Whatsapp::ReplySender.send_to(clarification.phone_number,
                                          "Ok, escríbelo con texto por favor. #{Questions.build_text(pending)}")
            return :ask_free_text
          end

          candidate.recalculate_missing_fields!
          candidate.recalculate_status!

          if clarification.all_candidates_resolved?
            complete_session!(clarification)
            :completed
          else
            follow_up(clarification)
          end
        end
      rescue StandardError => e
        Rails.logger.error("[Clarification::Resolver] tap failed: #{e.message}")
        Whatsapp::ReplySender.send_to(clarification.phone_number,
                                      "Tuve un problema procesando tu respuesta, inténtalo de nuevo 🙏")
        :error
      end

      def candidates_context(clarification)
        clarification.pending_candidates.each_with_index.map do |candidate, index|
          {
            index: index + 1,
            description: candidate.description,
            amount: candidate.amount,
            date: candidate.date,
            category: candidate.category&.name || candidate.category_suggestion,
            money_source: candidate.money_source&.name,
            missing_fields: candidate.missing_fields
          }
        end
      end

      # Vocabulary the LLM may use to resolve money-source references.
      # Only PAYMENT SOURCES: loans and the like are never valid answers
      # for "what paid this expense".
      def money_source_identifiers(user)
        user.money_sources.active.payment_sources.includes(recognition: :recognition_identifiers)
            .flat_map { |source| [ source.name, source.recognition_identifiers.select(&:confirmed?).map(&:value) ] }
      end

      # A reply like "sí/ok/dale" confirms a pending category proposal.
      def confirms?(reply_text)
        reply_text.to_s.strip.match?(/\A(s[ií]|ok|claro|dale|va|correcto|confirmar|crear)\z/i)
      end

      # Stores the proposed name and asks the user for confirmation with
      # deterministic Sí/No buttons (the proposal turn never consumes the
      # follow-up limit).
      def propose_category(clarification, name)
        proposed = name.to_s.strip.split.map(&:capitalize).join(" ").presence || name.to_s.strip
        clarification.update!(pending_category_name: proposed)
        Rails.logger.info "[Clarification::Resolver] Proposing new category \"#{proposed}\" for " \
                          "session=#{clarification.id}"
        Whatsapp::ReplySender.send_buttons(
          clarification.phone_number,
          "No tengo la categoría \"#{proposed}\" 🆕 ¿La creo?",
          [ { id: "newcategory:yes", title: "Sí, crear" }, { id: "newcategory:no", title: "No" } ]
        )
      end

      def discard_pending_category(clarification)
        Rails.logger.info "[Clarification::Resolver] Proposal \"#{clarification.pending_category_name}\" " \
                          "discarded for session=#{clarification.id}"
        clarification.update!(pending_category_name: nil)
      end

      # Confirms the pending proposal: resolves (or creates) the category,
      # applies it to every pending candidate still missing one, and lets
      # the normal flow continue.
      def apply_new_category(clarification)
        name = clarification.pending_category_name.to_s.strip
        clarification.update!(pending_category_name: nil)
        resolved = Categories::ClosestResolver.call(user: clarification.user, name: name)
        category = resolved.category ||
                   Category.create!(name: name.split.map(&:capitalize).join(" "),
                                    user: clarification.user, is_default: false, category_type: "expense")
        clarification.pending_candidates.select { |candidate| candidate.missing_fields.include?("category_id") }
                     .each do |candidate|
          candidate.update!(category_id: category.id)
          candidate.recalculate_missing_fields!
          candidate.recalculate_status!
        end
        Rails.logger.info "[Clarification::Resolver] Category \"#{category.name}\" applied for " \
                          "session=#{clarification.id}; pending=#{clarification.pending_candidates.count}"
        Whatsapp::ReplySender.send_to(clarification.phone_number,
                                      "✅ Categoría \"#{category.name}\" creada y asignada.")
        if clarification.all_candidates_resolved?
          complete_session!(clarification)
          :completed
        else
          follow_up(clarification)
        end
      end

      # Applies each resolution entry to its candidate by question index.
      # ONLY missing fields are written — resolved data is never overwritten.
      # Unresolved / unknown-index / unresolvable values leave the candidate
      # untouched. Returns the number of candidates modified.
      def apply_resolutions!(clarification, resolutions)
        pending = clarification.pending_candidates.to_a
        modified = 0

        resolutions.each do |entry|
          index = (entry[:index] || entry["index"]).to_i
          resolved = entry[:resolved] || entry["resolved"] || {}
          unresolved = entry[:unresolved] || entry["unresolved"] || resolved.blank?

          candidate = pending[index - 1]
          next if candidate.nil? || unresolved

          applied = apply_updates!(candidate, resolved)
          unless applied
            Rails.logger.info "[Clarification::Resolver] Resolution skipped for session=#{clarification.id} " \
                              "index=#{index} candidate=#{candidate&.description.inspect} " \
                              "resolved=#{resolved.inspect[0, 120]}"
            next
          end

          candidate.recalculate_missing_fields!
          candidate.recalculate_status!
          Rails.logger.info "[Clarification::Resolver] Resolution applied for session=#{clarification.id} " \
                            "candidate=#{candidate.description.inspect} " \
                            "missing_left=#{candidate.reload.missing_fields.inspect}"
          modified += 1
        end
        modified
      end

      def apply_updates!(candidate, updates)
        missing = candidate.missing_fields
        changed = false

        if missing.include?("amount")
          amount = parse_amount(updates["amount"])
          if amount.present? && amount.positive?
            candidate.amount = amount
            changed = true
          end
        end

        if missing.include?("date")
          date = ExpenseCandidate.parse_date(updates["date"])
          if date.present?
            candidate.date = date
            changed = true
          end
        end

        if missing.include?("description") && updates["description"].present?
          candidate.description = updates["description"].to_s.strip.presence
          changed = true
        end

        if missing.include?("category_id") && updates["category"].present?
          resolved = Categories::ClosestResolver.call(user: candidate.user, name: updates["category"])
          category = resolved.category ||
                     Category.create!(name: updates["category"].split.map(&:capitalize).join(" "),
                                      user: candidate.user, is_default: false, category_type: "expense")
          candidate.category_id = category.id
          changed = true
        end

        if missing.include?("money_source_id") && updates["money_source_hint"].present?
          source = MoneySources::Detector.call(user: candidate.user, text: updates["money_source_hint"])
          if source
            candidate.money_source_id = source.id
            changed = true
          end
        end

        candidate.save! if changed
        changed
      end

      def parse_amount(value)
        return nil if value.blank?

        BigDecimal(value.to_s.gsub(/[^\d.\-]/, ""))
      rescue ArgumentError, TypeError
        nil
      end

      # Converts every now-complete candidate immediately (idempotent via
      # confirm!) and closes the session when nothing is left pending. The
      # confirmation reaches WhatsApp as ONE batched message (Meta bills per
      # message) when several candidates complete; a single candidate keeps
      # the one-line format.
      def complete_session!(clarification)
        confirmed = []
        clarification.candidates.where(status: "ready", expense_id: nil).find_each do |candidate|
          candidate.confirm!
          confirmed << candidate
        end
        Rails.logger.info "[Clarification::Resolver] Completing session=#{clarification.id} with " \
                          "#{confirmed.size} confirmed candidate(s)"
        if confirmed.size == 1
          candidate = confirmed.first
          Whatsapp::ReplySender.send_to(
            clarification.phone_number,
            "✅ Gasto registrado: $#{format_amount(candidate.amount)} – #{candidate.description.presence || 'sin descripción'}"
          )
        elsif confirmed.size > 1
          lines = confirmed.each_with_index.map do |candidate, index|
            "#{index + 1}. #{candidate.description.presence || 'sin descripción'} — $#{format_amount(candidate.amount)}"
          end
          Whatsapp::ReplySender.send_to(
            clarification.phone_number,
            "✅ #{confirmed.size} gastos registrados:\n\n#{lines.join("\n")}"
          )
        end
        clarification.close!(:resolved) if clarification.all_candidates_resolved?
      end

      # Sends the next round question and either keeps the session pending
      # or abandons it once the follow-up limit is reached (remaining
      # candidates stay needs_review — no infinite loops). The question goes
      # through Questions.deliver so a round that leaves a single pending
      # candidate uses its interactive list.
      def follow_up(clarification, custom_question = nil)
        if clarification.follow_ups_exhausted?
          abandon(clarification)
          return :abandoned
        end

        if custom_question
          question = custom_question
          Whatsapp::ReplySender.send_to(clarification.phone_number, question)
        else
          question = Questions.deliver(clarification)
        end
        clarification.update!(question: question, questions_count: clarification.questions_count + 1)
        Rails.logger.info "[Clarification::Resolver] Follow-up sent for session=#{clarification.id} " \
                          "question=#{clarification.questions_count} " \
                          "pending=#{clarification.pending_candidates.map(&:description).inspect}"
        :follow_up
      end

      def abandon(clarification)
        clarification.close!(:abandoned)
        Rails.logger.warn "[Clarification::Resolver] Session=#{clarification.id} abandoned " \
                          "(follow-up limit reached); candidates stay needs_review"
        Whatsapp::ReplySender.send_to(
          clarification.phone_number,
          "Dejé la aclaración pendiente; los gastos quedaron guardados para revisión manual en el Expense Tracker."
        )
      end

      def format_amount(amount)
        ActionController::Base.helpers.number_to_currency(amount, unit: "", delimiter: ".", separator: ",",
                                                          precision: 0)
      end
    end
  end
end
