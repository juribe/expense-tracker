# frozen_string_literal: true

require "test_helper"

# Whatsapp::MediaFetcher: downloads a WhatsApp Cloud API media message
# (voice note, photo) and returns it as a base64 data URI ready for the
# Expenses pipeline inputs.
class Whatsapp::MediaFetcherTest < ActiveSupport::TestCase
  MEDIA_ID = "MEDIA123"
  MEDIA_URL = "https://lookaside.fbsbx.com/whatsapp_medium/MEDIA123"

  setup do
    ENV["WHATSAPP_ACCESS_TOKEN"] = "token123"
    ENV["WHATSAPP_BUSINESS_PHONE_NUMBER_ID"] = "110497245015457"
  end

  FakeResponse = Struct.new(:code, :body)

  def stub_http(media_url_response:, media_url_body:, download_response:, download_body:)
    metadata = FakeResponse.new(media_url_response, media_url_body)
    binary = FakeResponse.new(download_response, download_body)
    fake_http = Object.new
    fake_http.define_singleton_method(:use_ssl=) { |_| }
    fake_http.define_singleton_method(:request) { |*_args| binary }
    new_handler = ->(*_args) { fake_http }
    handler = ->(uri) { uri.to_s.include?("graph.facebook.com") ? metadata : binary }
    stub_method(Net::HTTP, :get_response, handler) do
      stub_method(Net::HTTP, :new, new_handler) { yield }
    end
  end

  test "fetches the media URL and returns the binary as a data URI" do
    response = nil
    stub_http(
      media_url_response: "200",
      media_url_body: { url: MEDIA_URL, mime_type: "audio/ogg" }.to_json,
      download_response: "200",
      download_body: "binary-audio"
    ) do
      response = Whatsapp::MediaFetcher.call(media_id: MEDIA_ID, mime_type: "audio/ogg")
    end

    assert_equal "data:audio/ogg;base64,#{Base64.strict_encode64("binary-audio")}", response
  end

  test "strips mime parameters so the data URI stays parseable" do
    response = nil
    stub_http(
      media_url_response: "200",
      media_url_body: { url: MEDIA_URL, mime_type: "audio/ogg; codecs=opus" }.to_json,
      download_response: "200",
      download_body: "binary-audio"
    ) do
      response = Whatsapp::MediaFetcher.call(media_id: MEDIA_ID, mime_type: "audio/ogg; codecs=opus")
    end

    assert_equal "data:audio/ogg;base64,#{Base64.strict_encode64("binary-audio")}", response
  end

  test "returns nil when the metadata lookup fails" do
    response = nil
    stub_http(
      media_url_response: "404",
      media_url_body: { error: { message: "not found" } }.to_json,
      download_response: "200",
      download_body: ""
    ) do
      response = Whatsapp::MediaFetcher.call(media_id: MEDIA_ID, mime_type: "audio/ogg")
    end

    assert_nil response
  end

  test "returns nil when the download fails" do
    response = nil
    stub_http(
      media_url_response: "200",
      media_url_body: { url: MEDIA_URL, mime_type: "audio/ogg" }.to_json,
      download_response: "403",
      download_body: "denied"
    ) do
      response = Whatsapp::MediaFetcher.call(media_id: MEDIA_ID, mime_type: "audio/ogg")
    end

    assert_nil response
  end

  test "returns nil without credentials" do
    ENV.delete("WHATSAPP_ACCESS_TOKEN")

    assert_nil Whatsapp::MediaFetcher.call(media_id: MEDIA_ID, mime_type: "audio/ogg")
  end
end
