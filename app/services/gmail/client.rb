# frozen_string_literal: true

require "base64"
require "cgi"
require "json"
require "net/http"
require "time"
require "uri"

module Gmail
  # Thin read-only client for the Gmail REST API v1 using Net::HTTP.
  #
  #   client = Gmail::Client.new(connection)
  #   ids    = client.list_messages(query: "from:(bank.com) newer_than:7d")
  #   email  = client.get_message(ids.first["id"])
  #     # => { "id"=>"...", "subject"=>"...", "body_text"=>"...", "internal_date"=>Time }
  class Client
    API_BASE = "https://gmail.googleapis.com/gmail/v1/users/me"
    LIST_PAGE_SIZE = 50

    class Error < StandardError; end

    def initialize(connection)
      @connection = connection
    end

    # Returns an array of message stubs ({ "id" => ..., "threadId" => ... }).
    def list_messages(query:, max_results: 25)
      uri = URI("#{API_BASE}/messages")
      uri.query = URI.encode_www_form(q: query, maxResults: [ max_results, LIST_PAGE_SIZE ].min)

      data = authenticated_get(uri)
      Array(data["messages"])
    end

    # Fetches one message and returns it in normalized form:
    #   { id:, subject:, body_text:, internal_date: (Time or nil) }
    def get_message(message_id)
      raw = authenticated_get(URI("#{API_BASE}/messages/#{URI.encode_www_form_component(message_id)}"))
      normalize(raw)
    end

    private

    def access_token
      @connection.fresh_access_token!
    end

    def authenticated_get(uri)
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Authorization"] = "Bearer #{access_token}"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 25

      response = http.request(request)
      raise Error, "Gmail API request failed (HTTP #{response.code})" unless response.code.to_i == 200

      JSON.parse(response.body)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
      raise Error, "Gmail API request failed (#{e.message})"
    end

    def normalize(raw)
      headers = raw.dig("payload", "headers") || []
      header = ->(name) { headers.find { |h| h["name"].to_s.casecmp(name).zero? }&.dig("value") }

      {
        id: raw["id"],
        subject: header.call("Subject").to_s,
        body_text: extract_body_text(raw),
        internal_date: parse_internal_date(raw["internalDate"] || header.call("Date")),
        snippet: raw["snippet"].to_s
      }
    end

    def parse_internal_date(value)
      return nil if value.blank?

      if value.match?(/\A\d+\z/)
        Time.zone.at(value.to_i / 1000.0)
      else
        Time.parse(value.to_s)
      end
    rescue ArgumentError, TypeError
      nil
    end

    # Walks the MIME tree preferring text/plain; falls back to tag-stripped HTML.
    def extract_body_text(raw)
      payload = raw["payload"] || {}
      text = find_text(payload, "text/plain") || find_text(payload, "text/html")
      return "" if text.blank?

      strip_html(text)
    end

    def find_text(part, mime_prefix)
      mime = part["mimeType"].to_s
      data = part.dig("body", "data")
      return decode_body(data) if mime.start_with?(mime_prefix) && data.present?

      Array(part["parts"]).each do |child|
        found = find_text(child, mime_prefix)
        return found if found.present?
      end

      nil
    end

    def decode_body(data)
      Base64.urlsafe_decode64(data)
    rescue ArgumentError
      ""
    end

    def strip_html(text)
      plain = text.gsub(/<style[^>]*>.*?<\/style>/im, " ")
                  .gsub(/<script[^>]*>.*?<\/script>/im, " ")
                  .gsub(/<[^>]+>/, " ")
      CGI.unescapeHTML(plain).gsub(/\s+/, " ").strip
    end
  end
end
