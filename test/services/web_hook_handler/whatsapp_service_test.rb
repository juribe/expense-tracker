# frozen_string_literal: true

require "test_helper"

# WebHookHandler::WhatsappService: routes incoming WhatsApp Cloud API message
# events. CONNECT commands go to Whatsapp::ConnectService; normal messages
# resolve the user through the active WhatsappConnection (via
# WhatsappIdentity); messages from unconnected numbers get connection
# instructions and never create expenses.
class WebHookHandlerWhatsappServiceTest < ActiveSupport::TestCase
  PHONE_NUMBER_ID = "110497245015457"
  OWNER_WA_ID = "573001112233"

  setup do
    @user = User.create!(
      name: "Whatsapp Service User",
      email: "whatsapp_service_test@example.com",
      password: "password123"
    )
    restaurants_category
  end

  def message_payload(text: nil, type: nil, caption: nil, sender: OWNER_WA_ID, media_id: "media_1", mime: nil,
                      interactive: nil)
    message = if type
                { id: "wamid.#{SecureRandom.hex(4)}", from: sender, timestamp: "1727450000", type: type }
    else
                { id: "wamid.#{SecureRandom.hex(4)}", from: sender, timestamp: "1727450000",
                  type: "text", text: { body: text } }
    end
    message[:audio] = { id: media_id, mime_type: mime || "audio/ogg" } if type == "audio"
    message[:image] = { id: media_id, mime_type: mime || "image/jpeg", caption: caption }.compact if type == "image"
    message[:video] = { id: media_id, mime_type: "video/mp4" } if type == "video"
    message[:interactive] = interactive if interactive

    {
      object: "whatsapp_business_account",
      entry: [ {
        id: "waba_id",
        changes: [ {
          field: "messages",
          value: {
            messaging_product: "whatsapp",
            metadata: { display_phone_number: "5712345678", phone_number_id: PHONE_NUMBER_ID },
            contacts: [ { profile: { name: "Jose" }, wa_id: sender } ],
            messages: [ message ]
          }
        } ]
      } ]
    }.to_json
  end

  def connect_user!
    identity = WhatsappIdentity.claim_for!(@user, OWNER_WA_ID)
    WhatsappConnection.create!(user: @user, whatsapp_identity: identity, connected_at: Time.current)
  end

  # The test DB is seeded with default categories; reuse rather than duplicate.
  def restaurants_category
    Category.find_by(name: "Restaurants") ||
      Category.create!(name: "Restaurants", is_default: true, category_type: "expense")
  end

  def start_clarification(candidate)
    session = @user.expense_clarifications.create!(phone_number: OWNER_WA_ID, question: "¿Con qué fuente?",
                                                   questions_count: 1)
    session.expense_clarification_candidates.create!(expense_candidate: candidate,
                                                     missing_fields: candidate.missing_fields)
    session
  end

  test "a ready candidate auto-confirms into a final Expense; needs_review stays for review" do
    connect_user!
    ready_candidate = @user.expense_candidates.create!(
      amount: 50_000,
      date: Date.current,
      description: "almuerzo",
      source: "whatsapp",
      status: "ready",
      category: restaurants_category
    )
    review_candidate = @user.expense_candidates.create!(
      amount: 12_000,
      date: Date.current,
      description: "compra rara",
      source: "whatsapp",
      status: "needs_review",
      missing_fields: [ :category_id ]
    )
    replies = []
    texts = []
    lists = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Whatsapp::ReplySender, :send_list,
                  ->(phone, header, rows, **_opts) { lists << [ phone, header, rows ] }) do
        stub_method(Expenses::Processor, :call, ->(**_kwargs) {
          Expenses::Result.new(candidates: [ ready_candidate, review_candidate ], errors: [], engine: "test")
        }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
        end
      end
    end
    replies = texts + lists

    assert_equal "confirmed", ready_candidate.reload.status
    assert ready_candidate.expense_id.present?
    # Transaction normalizes expense amounts to negative (money out).
    assert_equal 50_000, @user.expenses.find(ready_candidate.expense_id).amount.abs
    assert_equal "needs_review", review_candidate.reload.status
    assert_nil review_candidate.expense_id
    # The incomplete candidate starts a clarification session and is asked one
    # field at a time: the category question arrives as an interactive list.
    session = @user.expense_clarifications.pending.last
    assert_not_nil session
    assert session.candidate_ids.include?(review_candidate.id)
    assert lists.any? { |(_, header, rows)| header.include?("compra rara") &&
                                              header.include?("¿En qué categoría encaja?") &&
                                              rows.any? { |row| row[:id].start_with?("category:") } }
    assert texts.none? { |(_, text)| text.include?("¿Con qué fuente de dinero se pagó?") }
  end

  test "confirmations are sent BEFORE the clarification question" do
    connect_user!
    ready_candidate = @user.expense_candidates.create!(
      amount: 50_000,
      date: Date.current,
      description: "almuerzo",
      source: "whatsapp",
      status: "ready",
      category: restaurants_category
    )
    review_candidate = @user.expense_candidates.create!(
      amount: 12_000,
      date: Date.current,
      description: "compra rara",
      source: "whatsapp",
      status: "needs_review",
      missing_fields: [ :money_source_id ]
    )
    sent = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { sent << text }) do
      stub_method(Whatsapp::ReplySender, :send_list,
                  ->(_phone, header, _rows, **_opts) { sent << header }) do
        stub_method(Expenses::Processor, :call, ->(**_kwargs) {
          Expenses::Result.new(candidates: [ ready_candidate, review_candidate ], errors: [], engine: "test")
        }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
        end
      end
    end

    confirmations = sent.each_index.select { |i| sent[i].include?("✅") }
    questions = sent.each_index.select { |i| sent[i].include?("¿En qué categoría encaja?") }

    assert_equal 1, confirmations.size, "confirmations: #{sent.inspect}"
    assert_equal 1, questions.size, "questions: #{sent.inspect}"
    assert_operator confirmations.first, :<, questions.first,
                    "confirmation must arrive before the clarification question: #{sent.inspect}"
  end

  test "a re-sent interactive reply without a pending session gets a friendly reply" do
    connect_user!
    texts = []
    lists = []
    interactive = { type: "list_reply", list_reply: { id: "category:1", title: "Restaurants" } }
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Whatsapp::ReplySender, :send_list, ->(*_args, **_opts) { true }) do
    WebHookHandler::WhatsappService.call(
      raw_body: message_payload(type: "interactive", interactive: interactive)
    )
      end
    end

    assert texts.any? { |(_, text)| text.include?("no hay ninguna aclaración pendiente") }, texts.inspect
    assert lists.empty?
  end

  test "an incomplete candidate starts a clarification with an interactive source list" do
    connect_user!
    @user.money_sources.create!(name: "Davibank", kind: "account")
    review_candidate = @user.expense_candidates.create!(
      amount: 12_000,
      date: Date.current,
      description: "compra rara",
      source: "whatsapp",
      status: "needs_review",
      category: restaurants_category,
      missing_fields: [ :money_source_id ]
    )
    texts = []
    lists = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Whatsapp::ReplySender, :send_list,
                  ->(phone, header, rows, **_opts) { lists << [ phone, header, rows ] }) do
        stub_method(Expenses::Processor, :call, ->(**_kwargs) {
          Expenses::Result.new(candidates: [ review_candidate ], errors: [], engine: "test")
        }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 12 mil"))
        end
      end
    end

    session = @user.expense_clarifications.pending.last
    assert_not_nil session
    assert_equal [ review_candidate.id ], session.candidate_ids
    assert_equal 1, session.questions_count

    header, rows = lists.dig(0, 1), lists.dig(0, 2)
    assert_includes header, "compra rara"
    assert_includes header, "¿Con qué fuente de dinero se pagó?"
    assert rows.any? { |row| row[:title] == "Davibank" }
    assert rows.last[:id] == "other"
    assert_not_includes texts.join(" "), "money_source_id"
  end

  test "the fallback review notice uses APP_NAME when a session is already pending" do
    connect_user!
    pending_candidate = @user.expense_candidates.create!(
      amount: 12_000,
      date: Date.current,
      description: "compra rara",
      source: "whatsapp",
      status: "needs_review",
      missing_fields: [ :money_source_id ]
    )
    session = start_clarification(pending_candidate)
    new_candidate = @user.expense_candidates.create!(
      amount: 5_000,
      date: Date.current,
      description: "cine",
      source: "whatsapp",
      status: "needs_review",
      missing_fields: [ :money_source_id ]
    )
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Whatsapp::ReplySender, :send_list, ->(*_args, **_opts) { true }) do
        stub_method(Ai::Router, :call, ->(**_kwargs) {
          Ai::Router::Result.new(ok?: true, data: { resolutions: [], new_expense_text: "gasto nuevo" },
                                 confidence: 1.0, strategy: "test", error: nil)
        }) do
          stub_method(Expenses::Processor, :call, ->(**_kwargs) {
            Expenses::Result.new(candidates: [ new_candidate ], errors: [], engine: "test")
          }) do
            ENV["APP_NAME"] = "Mis Gastos"
            WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 5 mil en cine"))
          ensure
            ENV.delete("APP_NAME")
          end
        end
      end
    end

    assert texts.any? { |(_, text)| text.include?("Mis Gastos") }
  end

  test "the pipeline creates an ExpenseCandidate for the connected user" do
    connect_user!

    WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))

    candidate = @user.expense_candidates.last
    assert candidate.present?
    assert_equal "whatsapp", candidate.source
    assert_equal 50_000, candidate.amount
  end

  test "a message from an unconnected number creates no expense and replies with instructions" do
    replies = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { replies << [ phone, text ] }) do
      assert_no_difference -> { ExpenseCandidate.count } do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
      end
    end

    assert replies.any? { |(_, text)| text.include?("Conecta") || text.include?("conecta") }
  end

  test "a message from a number with only a disconnected connection is not processed" do
    connection = connect_user!
    connection.disconnect!

    assert_no_difference -> { ExpenseCandidate.count } do
      WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
    end
  end

  test "CONNECT commands are delegated to Whatsapp::ConnectService" do
    code = PendingWhatsappConnection.generate_for!(@user)
    replies = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { replies << [ phone, text ] }) do
      WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "CONNECT #{code}"))
    end

    identity = WhatsappIdentity.find_by(phone_number: OWNER_WA_ID)
    assert_equal @user.id, identity.claimed_by_user_id
    assert WhatsappConnection.active.exists?(user: @user, whatsapp_identity: identity)
    assert replies.any?
  end

  test "a voice note is processed through the audio channel with the downloaded media" do
    connect_user!
    data_uri = "data:audio/ogg;base64,#{Base64.strict_encode64("fake-audio")}"
    fetches = []
    processor_calls = []
    stub_method(Whatsapp::MediaFetcher, :call, ->(media_id:, mime_type:) {
      fetches << { media_id: media_id, mime_type: mime_type }
      data_uri
    }) do
      stub_method(Expenses::Processor, :call, ->(**kwargs) {
        processor_calls << kwargs
        Expenses::Result.new(candidates: [], errors: [], engine: "test")
      }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(type: "audio"))
      end
    end

    WebHookHandler::WhatsappService.call(raw_body: message_payload(type: "audio"))

    input = processor_calls.first[:input]
    assert_equal "audio", input.type
    assert_equal data_uri, input.audio_data
    assert_equal "whatsapp", processor_calls.first[:source]
    assert_equal({ media_id: "media_1", mime_type: "audio/ogg" }, fetches.first)
  end

  test "an image without caption is processed through the image channel" do
    connect_user!
    data_uri = "data:image/jpeg;base64,#{Base64.strict_encode64("fake-image")}"
    processor_calls = []
    stub_method(Whatsapp::MediaFetcher, :call, ->(media_id:, mime_type:) { data_uri }) do
      stub_method(Expenses::Processor, :call, ->(**kwargs) {
        processor_calls << kwargs
        Expenses::Result.new(candidates: [], errors: [], engine: "test")
      }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(type: "image"))
      end
    end


    input = processor_calls.first[:input]
    assert_equal "image", input.type
    assert_equal data_uri, input.image_data
  end

  test "an image with a caption is processed through the text_image channel" do
    connect_user!
    data_uri = "data:image/jpeg;base64,#{Base64.strict_encode64("fake-image")}"
    processor_calls = []
    stub_method(Whatsapp::MediaFetcher, :call, ->(media_id:, mime_type:) { data_uri }) do
      stub_method(Expenses::Processor, :call, ->(**kwargs) {
        processor_calls << kwargs
        Expenses::Result.new(candidates: [], errors: [], engine: "test")
      }) do
        WebHookHandler::WhatsappService.call(
          raw_body: message_payload(type: "image", caption: "almuerzo 50 mil")
        )
      end
    end

    input = processor_calls.first[:input]
    assert_equal "text_image", input.type
    assert_equal "almuerzo 50 mil", input.text
    assert_equal data_uri, input.image_data
  end

  test "a failed media download creates no candidate and replies with an error" do
    connect_user!
    replies = []
    stub_method(Whatsapp::MediaFetcher, :call, ->(media_id:, mime_type:) { nil }) do
      stub_method(Expenses::Processor, :call, ->(**_kwargs) {
        raise "processor must not run when the media download fails"
      }) do
        stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { replies << [ phone, text ] }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(type: "audio"))
        end
      end
    end

    assert replies.any? { |(_, text)| text.include?("descargar") }
  end

  test "an unsupported attachment type (video) is ignored without errors" do
    connect_user!

    assert_no_difference -> { ExpenseCandidate.count } do
      stub_method(Expenses::Processor, :call, ->(**_kwargs) { raise "must not run" }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(type: "video"))
      end
    end
  end

  test "payload without message events is ignored" do
    payload = {
      object: "whatsapp_business_account",
      entry: [ {
        id: "waba_id",
        changes: [ {
          field: "messages",
          value: {
            messaging_product: "whatsapp",
            metadata: { display_phone_number: "5712345678", phone_number_id: PHONE_NUMBER_ID },
            statuses: [ { id: "wamid.test1", status: "delivered" } ]
          }
        } ]
      } ]
    }.to_json

    assert_no_difference -> { ExpenseCandidate.count } do
      WebHookHandler::WhatsappService.call(raw_body: payload)
    end
  end

  test "a non-text (attachment) message from a connected number is ignored for now" do
    connect_user!
    payload = {
      object: "whatsapp_business_account",
      entry: [ {
        id: "waba_id",
        changes: [ {
          field: "messages",
          value: {
            messaging_product: "whatsapp",
            metadata: { display_phone_number: "5712345678", phone_number_id: PHONE_NUMBER_ID },
            contacts: [ { profile: { name: "Jose" }, wa_id: OWNER_WA_ID } ],
            messages: [ {
              id: "wamid.test2",
              from: OWNER_WA_ID,
              timestamp: "1727450000",
              type: "image",
              image: { id: "media_1", mime_type: "image/jpeg" }
            } ]
          }
        } ]
      } ]
    }.to_json

    assert_no_difference -> { ExpenseCandidate.count } do
      WebHookHandler::WhatsappService.call(raw_body: payload)
    end
  end

  test "a gibberish message is filtered before the pipeline and answered" do
    connect_user!
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      assert_no_difference -> { ExpenseCandidate.count } do
        stub_method(Expenses::Processor, :call, ->(**_kwargs) { raise "pipeline must not run" }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "sdksmdksmnkd skd kjs kdj"))
        end
      end
    end

    assert texts.any? { |(_, text)| text.include?("No entendí") }
  end

  test "a pipeline failure always notifies the user instead of silence" do
    connect_user!
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      assert_no_difference -> { ExpenseCandidate.count } do
        stub_method(Expenses::Processor, :call, ->(**_kwargs) { raise "boom" }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
        end
      end
    end

    assert texts.any? { |(_, text)| text.include?("problema procesando") }
  end

  test "an unexpected failure while processing a message still notifies the user" do
    connect_user!
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Expenses::Input, :from_params, ->(*_args) { raise "unexpected" }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
      end
    end

    assert texts.any? { |(_, text)| text.include?("problema procesando") }
  end

  test "duplicate webhook deliveries create only one candidate" do
    connect_user!
    body = message_payload(text: "gasté 50 mil en almuerzo")
    user = @user
    category = restaurants_category

    stub_method(Expenses::Processor, :call, ->(**_kwargs) {
      candidate = user.expense_candidates.create!(amount: 50_000, date: Date.current, description: "almuerzo",
                                                  source: "whatsapp", category: category)
      Expenses::Result.new(candidates: [ candidate ], errors: [], engine: "test")
    }) do
      WebHookHandler::WhatsappService.call(raw_body: body)
      WebHookHandler::WhatsappService.call(raw_body: body)
    end

    assert_equal 1, @user.expense_candidates.where(description: "almuerzo").count
  end

  test "cancelling the pending clarification keeps the candidate for review" do
    connect_user!
    candidate = @user.expense_candidates.create!(amount: 12_000, date: Date.current, description: "compra rara",
                                                 source: "whatsapp", status: "needs_review",
                                                 category: restaurants_category)
    session = start_clarification(candidate)
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Expenses::Processor, :call, ->(**_kwargs) { raise "pipeline must not run" }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "cancelar"))
      end
    end

    assert session.reload.cancelled?
    assert_equal "needs_review", candidate.reload.status
    assert_nil candidate.expense_id
    assert texts.any? { |(_, text)| text.include?("cancelé") }
  end

  test "an interactive tap replies to the pending candidate through the webhook" do
    connect_user!
    source = @user.money_sources.create!(name: "Nequi", kind: "wallet")
    candidate = @user.expense_candidates.create!(amount: 12_000, date: Date.current, description: "compra rara",
                                                 source: "whatsapp", status: "needs_review",
                                                 category: restaurants_category)
    session = start_clarification(candidate)
    stub_method(Whatsapp::ReplySender, :send_to, ->(_phone, _text) { true }) do
      stub_method(Ai::Router, :call, ->(**_kwargs) { raise "LLM must not be called for taps" }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(
          type: "interactive",
          interactive: { type: "list_reply", list_reply: { id: "source:#{source.id}", title: "Nequi" } }
        ))
      end
    end

    assert_equal source.id, candidate.reload.money_source_id
    assert_equal "confirmed", candidate.status
    assert session.reload.resolved?
  end

  test "a new expense while a clarification is pending survives as its own candidate" do
    connect_user!
    pending_candidate = @user.expense_candidates.create!(amount: 12_000, date: Date.current, description: "compra rara",
                                                         source: "whatsapp", status: "needs_review",
                                                         category: restaurants_category)
    session = start_clarification(pending_candidate)
    new_candidate = @user.expense_candidates.create!(amount: 80_000, date: Date.current, description: "cine",
                                                     source: "whatsapp", status: "ready",
                                                     category: restaurants_category)
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Whatsapp::ReplySender, :send_list, ->(*_args, **_opts) { true }) do
        stub_method(Ai::Router, :call, ->(**_kwargs) {
          Ai::Router::Result.new(ok?: true, data: { resolutions: [], new_expense_text: "gasto nuevo" },
                                 confidence: 1.0, strategy: "test", error: nil)
        }) do
          stub_method(Expenses::Processor, :call, ->(**_kwargs) {
            Expenses::Result.new(candidates: [ new_candidate ], errors: [], engine: "test")
          }) do
            WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 80 mil en cine"))
          end
        end
      end
    end

    # The new expense was confirmed; the pending clarification and its
    # candidate are untouched.
    assert_equal "confirmed", new_candidate.reload.status
    assert session.reload.pending?
    assert_equal "needs_review", pending_candidate.reload.status
    assert_equal 1, @user.expense_clarifications.where(status: "pending").count
  end

  test "a reply with both a clarification answer and a new expense handles both" do
    connect_user!
    source = @user.money_sources.create!(name: "Nequi", kind: "wallet")
    pending_candidate = @user.expense_candidates.create!(amount: 12_000, date: Date.current, description: "compra rara",
                                                         source: "whatsapp", status: "needs_review",
                                                         category: restaurants_category)
    session = start_clarification(pending_candidate)
    new_candidate = @user.expense_candidates.create!(amount: 80_000, date: Date.current, description: "cine",
                                                     source: "whatsapp", status: "ready",
                                                     category: restaurants_category)
    texts = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { texts << [ phone, text ] }) do
      stub_method(Ai::Router, :call, ->(**_kwargs) {
        Ai::Router::Result.new(
          ok?: true,
          data: { resolutions: [ { "index" => 1, "resolved" => { "money_source_hint" => "nequi" } } ],
                  new_expense_text: "80 mil en cine" },
          confidence: 1.0, strategy: "test", error: nil
        )
      }) do
        stub_method(Expenses::Processor, :call, ->(**_kwargs) {
          Expenses::Result.new(candidates: [ new_candidate ], errors: [], engine: "test")
        }) do
          WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "nequi. También gasté 80 mil en cine"))
        end
      end
    end

    # Both outcomes: the pending candidate was completed through the
    # clarification and the new expense went through the normal pipeline.
    assert_equal source.id, pending_candidate.reload.money_source_id
    assert_equal "confirmed", pending_candidate.status
    assert session.reload.resolved?
    assert_equal "confirmed", new_candidate.reload.status
    assert new_candidate.expense_id.present?
    assert_equal 0, @user.expense_clarifications.where(status: "pending").count
  end
end
