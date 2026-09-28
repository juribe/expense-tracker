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
end
