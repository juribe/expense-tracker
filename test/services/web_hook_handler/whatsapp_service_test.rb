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

  def message_payload(text: nil, type: nil, caption: nil, sender: OWNER_WA_ID, media_id: "media_1", mime: nil)
    message = if type
                { id: "wamid.#{SecureRandom.hex(4)}", from: sender, timestamp: "1727450000", type: type }
    else
                { id: "wamid.#{SecureRandom.hex(4)}", from: sender, timestamp: "1727450000",
                  type: "text", text: { body: text } }
    end
    message[:audio] = { id: media_id, mime_type: mime || "audio/ogg" } if type == "audio"
    message[:image] = { id: media_id, mime_type: mime || "image/jpeg", caption: caption }.compact if type == "image"
    message[:video] = { id: media_id, mime_type: "video/mp4" } if type == "video"

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
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { replies << [ phone, text ] }) do
      stub_method(Expenses::Processor, :call, ->(**_kwargs) {
        Expenses::Result.new(candidates: [ ready_candidate, review_candidate ], errors: [], engine: "test")
      }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 50 mil en almuerzo"))
      end
    end

    assert_equal "confirmed", ready_candidate.reload.status
    assert ready_candidate.expense_id.present?
    # Transaction normalizes expense amounts to negative (money out).
    assert_equal 50_000, @user.expenses.find(ready_candidate.expense_id).amount.abs
    assert_equal "needs_review", review_candidate.reload.status
    assert_nil review_candidate.expense_id
    assert replies.any? { |(_, text)| text.include?("50.000") || text.include?("50,000") }
  end

  test "the needs_review reply names the expense and humanizes missing fields" do
    connect_user!
    review_candidate = @user.expense_candidates.create!(
      amount: 12_000,
      date: Date.current,
      description: "compra rara",
      source: "whatsapp",
      status: "needs_review",
      missing_fields: [ :money_source_id ]
    )
    replies = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { replies << [ phone, text ] }) do
      stub_method(Expenses::Processor, :call, ->(**_kwargs) {
        Expenses::Result.new(candidates: [ review_candidate ], errors: [], engine: "test")
      }) do
        WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 12 mil"))
      end
    end

    reply = replies.join("\n")
    assert_includes reply, "compra rara"
    assert_includes reply, "fuente de dinero"
    assert_not_includes reply, "money_source_id"
  end

  test "the needs_review reply uses APP_NAME for the app name" do
    connect_user!
    review_candidate = @user.expense_candidates.create!(
      amount: 12_000,
      date: Date.current,
      description: "compra rara",
      source: "whatsapp",
      status: "needs_review",
      missing_fields: [ :money_source_id ]
    )
    replies = []
    stub_method(Whatsapp::ReplySender, :send_to, ->(phone, text) { replies << [ phone, text ] }) do
      stub_method(Expenses::Processor, :call, ->(**_kwargs) {
        Expenses::Result.new(candidates: [ review_candidate ], errors: [], engine: "test")
      }) do
        ENV["APP_NAME"] = "Mis Gastos"
        WebHookHandler::WhatsappService.call(raw_body: message_payload(text: "gasté 12 mil"))
      ensure
        ENV.delete("APP_NAME")
      end
    end

    assert replies.any? { |(_, text)| text.include?("Mis Gastos") }
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
end
