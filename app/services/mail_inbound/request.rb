# frozen_string_literal: true

module MailInbound
  # Request
  # Provider-neutral snapshot of an inbound webhook request.
  Request = Struct.new(:raw_body, :headers, :params, :content_type, keyword_init: true) do
    def header(name)
      target = name.to_s.downcase.tr("_", "-")
      pair = headers.find do |key, _value|
        key.to_s.downcase.sub(/\Ahttp[_-]/, "").tr("_", "-") == target
      end
      pair ? pair.last.to_s : ""
    end
  end
end
