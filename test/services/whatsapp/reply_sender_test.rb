# frozen_string_literal: true

require "test_helper"

# Whatsapp::ReplySender.send_list — builds the WhatsApp interactive list
# payload respecting Meta's field length limits (header ≤ 60, row title ≤ 24,
# description ≤ 72).
class Whatsapp::ReplySenderTest < ActiveSupport::TestCase
  def capture_list_payload(text, rows)
    delivered = nil
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:request) do |_request, body|
      delivered = JSON.parse(body)
      success = Object.new
      success.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      success.define_singleton_method(:code) { "200" }
      success
    end
    stub_method(ENV, :[], lambda { |key|
      case key
      when "WHATSAPP_ACCESS_TOKEN" then "token"
      when "WHATSAPP_BUSINESS_PHONE_NUMBER_ID" then "110497245015457"
      end
    }) do
      stub_method(Net::HTTP, :new, ->(*_args) { fake_http }) do
        Whatsapp::ReplySender.send_list("573001112233", text, rows)
      end
    end
    delivered
  end

  test "uses the fixed header and keeps the full question in the body" do
    long_question = 'Registré "Compra Olimpica" de $30.000 del 27/09/2026. ¿Con qué fuente de dinero se pagó?'
    payload = capture_list_payload(long_question, [ { id: "source:1", title: "Davibank" } ])

    interactive = payload["interactive"]
    assert_equal "Información faltante", interactive["header"]["text"]
    assert interactive["header"]["text"].length <= 60
    assert_equal long_question, interactive["body"]["text"]
    assert_equal "source:1", interactive["action"]["sections"].first["rows"].first["id"]
  end

  test "truncates row titles and descriptions" do
    payload = capture_list_payload("¿Fuente?", [ { id: "source:1", title: "T" * 40,
                                                   description: "D" * 100 } ])

    row = payload["interactive"]["action"]["sections"].first["rows"].first
    assert row["title"].length <= 24
    assert row["description"].length <= 72
  end

  test "rejects an empty or oversized row list" do
    assert_raises(ArgumentError) do
      Whatsapp::ReplySender.send_list("573001112233", "¿Fuente?", [])
    end
    assert_raises(ArgumentError) do
      Whatsapp::ReplySender.send_list("573001112233", "¿Fuente?", Array.new(11) { |i| { id: "r#{i}", title: "x" } })
    end
  end

  # Transient Meta API failures (throttling, rate limits, network hiccups)
  # are retried with a short backoff; permanent rejections are not.
  def deliver_with_responses(phone_number:, payload_body: "{}", responses:, sleep_calls: [])
    responses = responses.dup
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:request) do |_request, _body|
      code = responses.shift
      raise Net::ReadTimeout if code == :timeout

      response = Object.new
      response.define_singleton_method(:code) { code }
      response.define_singleton_method(:body) { "{}" }
      response.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess ? code == "200" : false }
      response
    end
    stub_method(ENV, :[], lambda { |key|
      case key
      when "WHATSAPP_ACCESS_TOKEN" then "token"
      when "WHATSAPP_BUSINESS_PHONE_NUMBER_ID" then "110497245015457"
      end
    }) do
      stub_method(Net::HTTP, :new, ->(*_args) { fake_http }) do
        stub_method(Whatsapp::ReplySender, :sleep, ->(seconds) { sleep_calls << seconds }) do
          Whatsapp::ReplySender.send_to(phone_number, "hola")
        end
      end
    end
  end

  test "retries a transient service error and succeeds" do
    calls = []
    delivered = deliver_with_responses(phone_number: "573001112233", responses: [ "500", "200" ],
                                       sleep_calls: calls)

    assert delivered
    assert_equal [ 1 ], calls
  end

  test "retries rate limits, timeouts and unavailable service" do
    calls = []
    delivered = deliver_with_responses(phone_number: "573001112233",
                                       responses: [ :timeout, "429", "200" ], sleep_calls: calls)

    assert delivered
    assert_equal [ 1, 2 ], calls
  end

  test "gives up after the retry limit and logs the last failure" do
    calls = []
    delivered = deliver_with_responses(phone_number: "573001112233",
                                       responses: [ "500", "500", "500", "500" ], sleep_calls: calls)

    refute delivered
    assert_equal [ 1, 2 ], calls
  end

  test "does not retry permanent client errors" do
    calls = []
    delivered = deliver_with_responses(phone_number: "573001112233",
                                       responses: [ "400", "400" ], sleep_calls: calls)

    refute delivered
    assert calls.empty?
  end

  test "send_buttons builds an interactive button payload with reply ids and titles" do
    delivered = nil
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:request) do |_request, body|
      delivered = JSON.parse(body)
      success = Object.new
      success.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      success.define_singleton_method(:code) { "200" }
      success
    end
    stub_method(ENV, :[], lambda { |key|
      case key
      when "WHATSAPP_ACCESS_TOKEN" then "token"
      when "WHATSAPP_BUSINESS_PHONE_NUMBER_ID" then "110497245015457"
      end
    }) do
      stub_method(Net::HTTP, :new, ->(*_args) { fake_http }) do
        Whatsapp::ReplySender.send_buttons(
          "573001112233",
          "¿La creo?",
          [ { id: "newcategory:yes", title: "Sí, crear" }, { id: "newcategory:no", title: "No" } ]
        )
      end
    end

    interactive = delivered["interactive"]
    assert_equal "button", interactive["type"]
    assert_equal "¿La creo?", interactive["body"]["text"]
    buttons = interactive["action"]["buttons"]
    assert_equal "newcategory:yes", buttons.first["reply"]["id"]
    assert_equal "Sí, crear", buttons.first["reply"]["title"]
    assert_equal "newcategory:no", buttons.last["reply"]["id"]
  end

  test "send_buttons truncates long titles and rejects bad button lists" do
    delivered = nil
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:request) do |_request, body|
      delivered = JSON.parse(body)
      success = Object.new
      success.define_singleton_method(:is_a?) { |klass| klass == Net::HTTPSuccess }
      success.define_singleton_method(:code) { "200" }
      success
    end
    stub_method(ENV, :[], lambda { |key|
      case key
      when "WHATSAPP_ACCESS_TOKEN" then "token"
      when "WHATSAPP_BUSINESS_PHONE_NUMBER_ID" then "110497245015457"
      end
    }) do
      stub_method(Net::HTTP, :new, ->(*_args) { fake_http }) do
        Whatsapp::ReplySender.send_buttons(
          "573001112233", "¿La creo?",
          [ { id: "a", title: "T" * 40 }, { id: "b", title: "No" } ]
        )
      end
    end

    assert delivered["interactive"]["action"]["buttons"].first["reply"]["title"].length <= 20

    assert_raises(ArgumentError) do
      Whatsapp::ReplySender.send_buttons("573001112233", "x", [])
    end
    assert_raises(ArgumentError) do
      Whatsapp::ReplySender.send_buttons("573001112233", "x", Array.new(4) { |i| { id: "b#{i}", title: "x" } })
    end
  end
end
