# frozen_string_literal: true

require "net/http"

# Whatsapp::MediaFetcher
# Downloads a WhatsApp Cloud API media message (voice note, photo) and returns
# it as a base64 data URI ready for the Expenses pipeline inputs. Requires
# WHATSAPP_ACCESS_TOKEN; returns nil (logging the cause) on any failure so the
# webhook can reply gracefully instead of raising.
#
# Example: Whatsapp::MediaFetcher.call(media_id: "MEDIA123", mime_type: "audio/ogg")
module Whatsapp
  class MediaFetcher
    GRAPH_URL = "https://graph.facebook.com/v23.0"

      # WhatsApp reports voice notes as "audio/ogg; codecs=opus": the mime
      # parameters break the Expenses data-URI parser (data:<mime>;base64,),
      # so only the bare type goes into the data URI.
      def self.call(media_id:, mime_type:)
        token = ENV["WHATSAPP_ACCESS_TOKEN"]
        return nil if token.blank?

        media_url = fetch_media_url(media_id, token)
        return nil unless media_url

        binary = download(media_url, token)
        return nil unless binary

        "data:#{mime_type.to_s.split(";").first.to_s.strip};base64,#{Base64.strict_encode64(binary)}"
    rescue StandardError => e
      Rails.logger.error "[MediaFetcher] Failed to fetch media #{media_id}: #{e.message}"
      nil
    end

    class << self
      private

      def fetch_media_url(media_id, token)
        uri = URI("#{GRAPH_URL}/#{media_id}?fields=url&access_token=#{CGI.escape(token)}")
        response = Net::HTTP.get_response(uri)
        unless response.code.to_s.start_with?("2")
          Rails.logger.error "[MediaFetcher] Media metadata lookup failed for #{media_id}: #{response.code}"
          return nil
        end
        JSON.parse(response.body)["url"]
      end

      def download(media_url, token)
        uri = URI(media_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{token}")
        response = http.request(request)
        unless response.code.to_s.start_with?("2")
          Rails.logger.error "[MediaFetcher] Media download failed: #{response.code}"
          return nil
        end
        response.body
      end
    end
  end
end
