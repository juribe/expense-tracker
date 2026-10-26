# frozen_string_literal: true

module MailInbound
  # Result
  # Outcome of accepting an inbound webhook at the HTTP boundary.
  Result = Struct.new(:status, :delivery, :message, :error, keyword_init: true) do
    def accepted?
      status == :accepted
    end

    def duplicate?
      status == :duplicate
    end
  end
end
