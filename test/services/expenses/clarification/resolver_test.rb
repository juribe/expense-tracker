# frozen_string_literal: true

require "test_helper"

# Expenses::Clarification::Resolver — conversational clarification flow for
# the incomplete expense candidates of a WhatsApp message. The flow is
# ARRAY-based end to end: sessions group multiple candidates, questions are
# grouped and the LLM resolver returns one resolution per matched candidate.
module Expenses
  module Clarification
    class ResolverTest < ActiveSupport::TestCase
      setup do
        @user = User.create!(
          name: "Clarification User",
          email: "clarification_test@example.com",
          password: "password123"
        )
        @davibank = @user.money_sources.create!(name: "Davibank", kind: "account")
        @nequi = @user.money_sources.create!(name: "Nequi", kind: "wallet")
        @efectivo = @user.money_sources.create!(name: "Efectivo", kind: "cash")
        @restaurants = Category.find_by(name: "Restaurants") ||
                       Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
        @transport = Category.find_by(name: "Transporte") ||
                     Category.create!(name: "Transporte", is_default: true, category_type: "expense")
        @phone = "573001112233"
      end

      def stub_llm(data, new_category_name = nil)
        payload = new_category_name ? data.merge(new_category_name: new_category_name) : data
        result = Ai::Router::Result.new(ok?: true, data: payload, confidence: 1.0, strategy: "test", error: nil)
        stub_method(Ai::Router, :call, ->(**_kwargs) { result }) { yield }
      end

      # Captures every outbound message (text bodies and list headers) into a
      # local array so the stubs close over it regardless of stub self.
      def capture_replies
        sent = []
        stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, text) { sent << text }) do
          stub_method(Whatsapp::ReplySender, :send_list, ->(_phone, header, _rows, **_opts) { sent << header }) do
            yield
          end
        end
        sent
      end

      def create_candidate(**attrs)
        @user.expense_candidates.create!({ source: "whatsapp", status: "needs_review" }.merge(attrs))
      end

      # Captures the kwargs passed to Ai::Router.call inside the block so
      # tests can inspect the context lists the LLM actually sees.
      def capture_llm_contexts
        contexts = []
        stub_method(Ai::Router, :call, ->(**kwargs) { contexts << kwargs }) { yield }
        contexts
      end

      test "start_session! groups multiple incomplete candidates and asks one grouped question" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina")
        restaurante = create_candidate(amount: 80_000, date: Date.current, description: "Restaurante")

        session = nil
        replies = capture_replies do
          session = Expenses::Clarification::Resolver.start_session!(
            user: @user, phone_number: @phone, candidates: [ exito, gasolina, restaurante ],
            original_message: "40 mil en Éxito, 25 mil de gasolina y 80 mil en restaurante"
          )
        end

        assert_not_nil session
        assert session.pending?
        assert_equal [ exito.id, gasolina.id, restaurante.id ].sort, session.candidate_ids.sort
        assert_equal 1, session.questions_count
        question = replies.first
        assert_includes question, "Éxito — $40.000"
        assert_includes question, "Gasolina — $25.000"
        assert_includes question, "Restaurante — $80.000"
        assert_includes question, "mismo orden"
      end

      test "start_session! asks a direct question when only one candidate is incomplete" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        session = nil
        capture_replies do
          session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                     candidates: [ gasolina ])
        end

        assert_not_nil session
        assert session.question.include?("Gasolina")
        assert session.question.include?("¿Con qué fuente de dinero se pagó?")
      end

      test "a single candidate missing several fields is asked one field at a time with lists" do
        exito = create_candidate(amount: 50_000, date: Date.current, description: "Éxito")
        lists = []
        session = nil
        stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, _text) { true }) do
          stub_method(Whatsapp::ReplySender, :send_list,
                      ->(_phone, header, rows, **_opts) { lists << [ header, rows ] }) do
            session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                       candidates: [ exito ])
          end
        end

        # First missing field (category) with its interactive list; the money
        # source question comes on the next turn.
        assert_not_nil session
        assert_includes session.question, "¿En qué categoría encaja?"
        assert_not_includes session.question, "¿Con qué fuente de dinero se pagó?"
        assert lists.any? { |(header, rows)| header == session.question && rows.any? { |row| row[:id].start_with?("category:") } }

        # One reply can still resolve every missing field at once.
        outcome = nil
        capture_replies do
          outcome = stub_llm(resolutions: [ { "index" => 1,
                                              "resolved" => { "category" => "Alimentos", "money_source_hint" => "davibank" } } ],
                             new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "con davibank, alimento")
          end
        end

        assert_equal [ :completed, nil ], outcome
        assert_equal @davibank.id, exito.reload.money_source_id
        assert_equal "Alimentos", exito.category.name
        assert_equal "confirmed", exito.status
      end

      test "start_session! returns nil when everything is complete or a session is open" do
        complete = create_candidate(amount: 1_000, date: Date.current, description: "ok", category: @transport,
                                    money_source: @nequi)
        assert_nil Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                    candidates: [ complete ])

        incomplete = create_candidate(amount: 1_000, date: Date.current, description: "otro")
        Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone, candidates: [ incomplete ])
        second = create_candidate(amount: 2_000, date: Date.current, description: "segunda")
        assert_nil Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                    candidates: [ second ])
      end

      test "one reply resolves all pending candidates and completes the session" do
        candidates = %w[Éxito Gasolina Restaurante].zip([ 40_000, 25_000, 80_000 ]).map do |description, amount|
          create_candidate(amount: amount, date: Date.current, description: description, money_source: @nequi)
        end
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: candidates)

        replies = nil
        outcome = nil
        replies = capture_replies do
          outcome = stub_llm(resolutions: [
                             { "index" => 1, "resolved" => { "category" => "Transporte" } },
                             { "index" => 2, "resolved" => { "category" => "Transporte" } },
                             { "index" => 3, "resolved" => { "category" => "Restaurants" } }
                           ], new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "transporte, transporte, restaurante")
          end
        end

        assert_equal [ :completed, nil ], outcome
        assert session.reload.resolved?
        assert_equal "Transporte", candidates[0].reload.category.name
        assert_equal "Restaurants", candidates[2].reload.category.name
        assert candidates.all? { |candidate| candidate.reload.status == "confirmed" }
        assert candidates.all? { |candidate| candidate.expense_id.present? }
        assert_equal 3, @user.expenses.where("description IN (?)", %w[Éxito Gasolina Restaurante]).count

        # ONE confirmation message for the whole batch (Meta bills per message).
        confirmations = replies.grep(/✅/)
        assert_equal 1, confirmations.size
        confirmation = confirmations.first
        assert confirmation.include?("3 gastos registrados")
        assert confirmation.include?("1. Éxito — $40.000")
        assert confirmation.include?("2. Gasolina — $25.000")
        assert confirmation.include?("3. Restaurante — $80.000")
      end

      test "a reply resolving only some candidates keeps the rest pending and asks again" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ exito, gasolina ])

        outcome = nil
        capture_replies do
          outcome = stub_llm(resolutions: [ { "index" => 2, "resolved" => { "money_source_hint" => "efectivo" } } ],
                             new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "gasolina en efectivo")
          end
        end

        assert_equal [ :follow_up, nil ], outcome
        assert session.reload.pending?
        assert_equal @davibank.class, MoneySource # sanity: no source invented for Éxito
        assert_nil exito.reload.money_source_id
        assert_equal "needs_review", exito.reload.status
        assert_equal [ exito.id ], session.pending_candidates.pluck(:id)
        assert session.question.include?("Éxito")
      end

      test "natural references (el primero, los dos últimos) match the right candidates" do
        candidates = %w[Éxito Gasolina Restaurante].zip([ 40_000, 25_000, 80_000 ]).map do |description, amount|
          create_candidate(amount: amount, date: Date.current, description: description, category: @transport)
        end
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: candidates)

        capture_replies do
          stub_llm(resolutions: [
                     { "index" => 1, "resolved" => { "money_source_hint" => "davibank" } },
                     { "index" => 2, "resolved" => { "money_source_hint" => "efectivo" } },
                     { "index" => 3, "resolved" => { "money_source_hint" => "efectivo" } }
                   ], new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "el primero davibank, los dos últimos efectivo")
          end
        end

        assert_equal @davibank.id, candidates[0].reload.money_source_id
        assert_equal @efectivo.id, candidates[1].reload.money_source_id
        assert_equal @efectivo.id, candidates[2].reload.money_source_id
        assert session.reload.resolved?
      end

      test "an ambiguous reply asks a follow-up without consuming progress" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ exito ])
        count = session.questions_count

        outcome = nil
        capture_replies do
          outcome = stub_llm(resolutions: [ { "index" => 1, "unresolved" => true } ], new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "pues no sé")
          end
        end

        assert_equal [ :follow_up, nil ], outcome
        assert session.reload.pending?
        assert_equal count + 1, session.questions_count
        assert_equal "needs_review", exito.reload.status
      end

      test "mixed missing fields are asked one round at a time starting with the largest group" do
        sin_categoria = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        sin_fuente = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                      category: @transport)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ sin_categoria, sin_fuente ])

        # Round 1: the largest group (both miss the money source); the
        # category of Éxito is NOT asked yet.
        assert session.question.include?("el medio de pago")
        assert session.question.include?("1. Éxito — $40.000")
        assert session.question.include?("2. Gasolina — $25.000")
        refute session.question.include?("categor")

        # Round 2 follow-up: only Éxito still misses the category.
        capture_replies do
          stub_llm(resolutions: [ { "index" => 1, "resolved" => { "money_source_hint" => "davibank" } },
                                   { "index" => 2, "resolved" => { "money_source_hint" => "efectivo" } } ],
                   new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "davibank y efectivo")
          end
        end

        assert session.reload.pending?
        assert session.question.include?("¿En qué categoría encaja?")
        assert session.question.include?("Éxito")
        refute session.question.include?("Gasolina")
        assert_equal 2, session.questions_count
      end

      test "a round that leaves a single pending candidate across the session uses the interactive list" do
        sin_categoria = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        sin_fuente = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                      category: @transport)
        lists = []
        session = nil
        stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, _text) { true }) do
          stub_method(Whatsapp::ReplySender, :send_list,
                      ->(_phone, header, rows, **_opts) { lists << [ header, rows ] }) do
            session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                       candidates: [ sin_categoria, sin_fuente ])
          end
        end

        # Round 1: both candidates miss the money source → grouped text, no list.
        assert lists.empty?, "round 1 groups two candidates: no interactive list expected"

        stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, _text) { true }) do
          stub_method(Whatsapp::ReplySender, :send_list,
                      ->(_phone, header, rows, **_opts) { lists << [ header, rows ] }) do
            stub_llm(resolutions: [ { "index" => 2, "resolved" => { "money_source_hint" => "nequi" } } ],
                     new_expense_text: nil) do
              Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "gasolina con nequi")
            end
          end
        end

        # Only Éxito remains pending session-wide: its category asked via list.
        assert lists.any? { |(header, rows)| header == session.reload.question &&
                                              rows.any? { |row| row[:id].start_with?("category:") } }
      end

      test "a large group of candidates missing only the money source asks one grouped payment question" do
        candidates = %w[Éxito Gasolina Restaurante Farmacia Netflix].map do |description|
          create_candidate(amount: 10_000, date: Date.current, description: description, category: @transport)
        end
        session = nil
        replies = capture_replies do
          session = Expenses::Clarification::Resolver.start_session!(
            user: @user, phone_number: @phone, candidates: candidates,
            original_message: "40 en Éxito, 25 en gasolina, 80 en restaurante, 15 en farmacia y 30 en Netflix"
          )
        end

        question = replies.first
        candidates.each_with_index do |candidate, index|
          assert_includes question, "#{index + 1}. #{candidate.description} — $10.000"
        end
        assert_includes question, "el medio de pago"
        assert_includes question, "¿Con qué fuente de dinero se pagó?"
        refute_includes question, "categor"
        assert session.reload.pending?
      end

      test "a clearly new category is proposed with buttons before creating it" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina", money_source: @nequi)
        buttons = []
        replies = nil
        session = nil
        stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, text) { true }) do
          stub_method(Whatsapp::ReplySender, :send_buttons,
                      ->(_phone, text, btns, **_opts) { buttons << [ text, btns ]; true }) do
            stub_method(Whatsapp::ReplySender, :send_list, ->(*_args, **_opts) { false }) do
              session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                         candidates: [ gasolina ])

              # Free-text reply naming a category that does not exist: the
              # session proposes it with Sí/No buttons, creates NOTHING yet.
              outcome = nil
              replies = capture_replies do
                stub_llm({ resolutions: [] }, "Animacion") do
                  outcome = Expenses::Clarification::Resolver.handle_reply(clarification: session,
                                                                           reply_text: "animacion")
                end
              end
              assert_equal [ :category_proposed, nil ], outcome
            end
          end
        end

        assert_equal "Animacion", session.reload.pending_category_name
        assert_nil gasolina.reload.category_id
        assert_equal 1, session.questions_count, "the proposal turn does not consume follow-ups"
        assert buttons.any? { |(text, btns)| text.include?("Animacion") &&
                                              btns.map { |b| b[:id] } == [ "newcategory:yes", "newcategory:no" ] }
        assert replies.empty?, "no extra text is sent besides the buttons: #{replies.inspect}"

        # Tapping "Sí, crear" creates the category, applies it and completes.
        replies = nil
        outcome = nil
        replies = capture_replies do
          stub_method(Ai::Router, :call, ->(**_kwargs) { raise "LLM must not be called for taps" }) do
            outcome = Expenses::Clarification::Resolver.handle_tap(
              clarification: session, interactive_reply: { "id" => "newcategory:yes", "title" => "Sí, crear" }
            )
          end
        end

        assert_equal :completed, outcome
        category = Category.find_by(name: "Animacion", user: @user)
        assert_not_nil category
        assert_equal category.id, gasolina.reload.category_id
        assert_equal "confirmed", gasolina.status
        assert session.reload.resolved?
        assert_nil session.pending_category_name
        assert replies.any? { |text| text.include?("Animacion") && text.include?("✅") }
      end

      test "tapping No discards the proposal and re-asks the normal round" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina", money_source: @nequi)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])
        session.update!(pending_category_name: "Animacion")

        replies = nil
        outcome = nil
        replies = capture_replies do
          stub_method(Ai::Router, :call, ->(**_kwargs) { raise "LLM must not be called for the No tap" }) do
            outcome = Expenses::Clarification::Resolver.handle_tap(
              clarification: session, interactive_reply: { "id" => "newcategory:no", "title" => "No" }
            )
          end
        end

        assert_equal :follow_up, outcome
        assert_nil session.reload.pending_category_name
        assert_nil Category.find_by(name: "Animacion", user: @user)
        assert session.reload.pending?
        assert session.question.include?("Gasolina")
        assert_equal 2, session.questions_count
      end

      test "a text 'sí' confirms the pending proposal without the LLM" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina", money_source: @nequi)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])
        session.update!(pending_category_name: "Animacion")

        outcome = nil
        capture_replies do
          stub_method(Ai::Router, :call, ->(**_kwargs) { raise "LLM must not be called for a text confirmation" }) do
            outcome = Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "sí")
          end
        end

        assert_equal [ :completed, nil ], outcome
        category = Category.find_by(name: "Animacion", user: @user)
        assert_equal category.id, gasolina.reload.category_id
        assert_nil session.reload.pending_category_name
      end

      test "a non-confirmation reply discards the proposal and goes through the LLM" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina", money_source: @nequi)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])
        session.update!(pending_category_name: "Animacion")

        outcome = nil
        capture_replies do
          stub_llm(resolutions: [ { "index" => 1, "resolved" => { "category" => "Transporte" } } ],
                   new_expense_text: nil) do
            outcome = Expenses::Clarification::Resolver.handle_reply(clarification: session,
                                                                     reply_text: "no, mejor transporte")
          end
        end

        assert_equal [ :completed, nil ], outcome
        assert_nil session.reload.pending_category_name
        assert_equal "Transporte", gasolina.reload.category.name
        assert_nil Category.find_by(name: "Animacion", user: @user)
      end

      test "already resolved fields are never overwritten" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])

        capture_replies do
          stub_llm(resolutions: [ { "index" => 1,
                                    "resolved" => { "description" => "otra cosa", "money_source_hint" => "nequi" } } ],
                   new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "nequi")
          end
        end

        assert_equal "Gasolina", gasolina.reload.description
        assert_equal @nequi.id, gasolina.money_source_id
        assert session.reload.resolved?
      end

      test "a new expense fragment is returned while the session stays pending" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])

        outcome = nil
        capture_replies do
          outcome = stub_llm(resolutions: [ { "index" => 1, "resolved" => { "money_source_hint" => "nequi" } } ],
                             new_expense_text: "50 mil en supermercado con efectivo") do
            Expenses::Clarification::Resolver.handle_reply(
              clarification: session, reply_text: "nequi. También gasté 50 mil en supermercado con efectivo"
            )
          end
        end

        assert_equal [ :completed, "50 mil en supermercado con efectivo" ], outcome
        assert session.reload.resolved?
        assert_equal @nequi.id, gasolina.reload.money_source_id
      end

      test "nothing resolvable: follow-up without inventing values" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ exito ])

        outcome = nil
        capture_replies do
          outcome = stub_llm(resolutions: [], new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "mmm")
          end
        end

        assert_equal [ :follow_up, nil ], outcome
        assert_equal "needs_review", exito.reload.status
      end

      test "the follow-up limit abandons the session and leaves candidates for review" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ exito ])
        session.update!(questions_count: ExpenseClarification::MAX_QUESTIONS)

        outcome = nil
        replies = capture_replies do
          outcome = stub_llm(resolutions: [ { "index" => 1, "unresolved" => true } ], new_expense_text: nil) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "pues no sé")
          end
        end

        assert_equal [ :abandoned, nil ], outcome
        assert session.reload.abandoned?
        assert_equal "needs_review", exito.reload.status
        assert_nil exito.expense_id
        assert replies.any? { |text| text.include?("revisión manual") }
      end

      test "LLM failures keep the session pending without consuming follow-ups" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ exito ])
        count = session.questions_count

        replies = nil
        outcome = nil
        replies = capture_replies do
          outcome = stub_method(Ai::Router, :call, ->(**_kwargs) {
            Ai::Router::Result.new(ok?: false, data: nil, confidence: nil, strategy: "test", error: "down")
          }) do
            Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "efectivo")
          end
        end

        assert_equal [ :llm_error, nil ], outcome
        assert session.reload.pending?
        assert_equal count, session.questions_count
        assert replies.any? { |text| text.include?("No pude procesar") }
      end

      test "an interactive tap resolves the single pending candidate without the LLM" do
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])

        replies = nil
        outcome = nil
        replies = capture_replies do
          outcome = stub_method(Ai::Router, :call, ->(**_kwargs) { raise "LLM must not be called for taps" }) do
            Expenses::Clarification::Resolver.handle_tap(
              clarification: session, interactive_reply: { "id" => "source:#{@nequi.id}", "title" => "Nequi" }
            )
          end
        end

        assert_equal :completed, outcome
        assert_equal @nequi.id, gasolina.reload.money_source_id
        assert_equal "confirmed", gasolina.status
        assert session.reload.resolved?
        assert replies.any? { |text| text.include?("✅") }
      end

      test "the WhatsApp source list offers only payment sources (never loans)" do
        card = @user.money_sources.create!(name: "Tarjeta Davibank", kind: "credit_card")
        loan = @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        lists = []
        capture_replies do
          stub_method(Whatsapp::ReplySender, :send_list,
                      ->(_phone, header, rows, **_opts) { lists << [ header, rows ] }) do
            session = Expenses::Clarification::Resolver.start_session!(
              user: @user, phone_number: @phone, candidates: [ gasolina ]
            )
            assert_not_nil session
          end
        end

        source_rows = lists.flat_map { |(_, rows)| rows }
                           .select { |row| row[:id].start_with?("source:") }
        offered_ids = source_rows.map { |row| row[:id].sub("source:", "").to_i }
        assert_includes offered_ids, @davibank.id
        assert_includes offered_ids, @nequi.id
        assert_includes offered_ids, @efectivo.id
        assert_includes offered_ids, card.id
        assert_not_includes offered_ids, loan.id
      end

      test "a tapped non-payment source is ignored (backend guard)" do
        loan = @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina",
                                    category: @transport)
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])

        outcome = stub_method(Ai::Router, :call, ->(**_kwargs) { raise "LLM must not be called for taps" }) do
          Expenses::Clarification::Resolver.handle_tap(
            clarification: session, interactive_reply: { "id" => "source:#{loan.id}", "title" => loan.name }
          )
        end

        assert_equal :tap_ignored, outcome
        assert_nil gasolina.reload.money_source_id
      end

      test "the LLM context offers only payment sources as money-source vocabulary" do
        @user.money_sources.create!(name: "Tarjeta Davibank", kind: "credit_card")
        @user.money_sources.create!(name: "Crédito Vehículo", kind: "loan", sub_kind: "vehicle")
        gasolina = create_candidate(amount: 25_000, date: Date.current, description: "Gasolina")
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ gasolina ])

        contexts = capture_llm_contexts do
          stub_method(Whatsapp::ReplySender, :send_to, ->(*_args) {}) do
            stub_method(Whatsapp::ReplySender, :send_buttons, ->(*_args) {}) do
              Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "tarjeta davibank")
            end
          end
        end

        identifiers = contexts.flat_map { |c| Array(c.dig(:context, :money_source_identifiers)) }
        assert_includes identifiers, "Davibank"
        assert_includes identifiers, "Tarjeta Davibank"
        assert_includes identifiers, "Nequi"
        assert_includes identifiers, "Efectivo"
        assert_not_includes identifiers, "Crédito Vehículo"
      end

      test "a list delivery failure falls back to a plain text question" do
        exito = create_candidate(amount: 50_000, date: Date.current, description: "Éxito")
        texts = []
        session = nil
        stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, text) { texts << text }) do
          stub_method(Whatsapp::ReplySender, :send_list, ->(_phone, _header, _rows, **_opts) { false }) do
            session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                       candidates: [ exito ])
          end
        end

        assert_not_nil session
        assert texts.any? { |text| text.include?("¿En qué categoría encaja?") }
      end

      test "close! is atomic: a concurrent resolution wins once" do
        exito = create_candidate(amount: 40_000, date: Date.current, description: "Éxito")
        session = Expenses::Clarification::Resolver.start_session!(user: @user, phone_number: @phone,
                                                                   candidates: [ exito ])

        assert_equal 1, ExpenseClarification.where(id: session.id, status: "pending")
                                            .update_all(status: "resolved")
        refute session.reload.pending?
        refute session.close!(:cancelled)
        assert session.resolved?
      end

      test "webhook re-deliveries are claimed once by message id" do
        assert WhatsappInboundMessage.claim!("wamid.TEST1")
        refute WhatsappInboundMessage.claim!("wamid.TEST1")
        assert WhatsappInboundMessage.claim!("wamid.TEST2")
      end

      test "the expense resolver keeps its ARRAY-based contract" do
        # Regression guard: the normal pipeline must still return an array of
        # independent candidates and the clarification layer never changes it.
        result = Expenses::Processor.call(
          user: @user,
          input: Expenses::Input.from_params("text", { text: "gasté 50 mil en almuerzo y 20 mil en taxi" }),
          source: "whatsapp"
        )
        assert_kind_of Array, result.candidates
        assert result.candidates.size >= 1
        assert result.candidates.all? { |candidate| candidate.is_a?(ExpenseCandidate) && candidate.persisted? }
      end

      test "handle_reply closes a zombie session whose candidates are all resolved" do
        candidate = create_candidate(amount: 40_000, date: Date.current, description: "Éxito",
                                     category: @restaurants)
        session = Expenses::Clarification::Resolver.start_session!(
          user: @user, phone_number: @phone, candidates: [ candidate ], original_message: "40 mil en Éxito"
        )
        # Resolved outside the conversation (e.g. confirmed in the web app):
        # the session stays pending but has nothing left to clarify.
        candidate.confirm!

        outcome = Expenses::Clarification::Resolver.handle_reply(clarification: session, reply_text: "cualquier cosa")

        assert_equal [ :stale, nil ], outcome
        assert session.reload.resolved?
      end
    end
  end
end
