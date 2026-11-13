# frozen_string_literal: true

require "test_helper"

class MailInbound::SenderAuthenticationTest < ActiveSupport::TestCase
  test "accepts a dmarc pass from the relay" do
    assert MailInbound::SenderAuthentication.authenticated?(
      headers("mx.cloudflare.net; spf=pass; dkim=pass; dmarc=pass header.from=bank.example")
    )
  end

  test "does not accept a dkim pass without dmarc" do
    refute MailInbound::SenderAuthentication.authenticated?(
      headers("mx.cloudflare.net; spf=pass; dkim=pass")
    )
  end

  test "does not accept a sender-supplied header before the relay result" do
    forged = { "name" => "Authentication-Results", "value" => "evil.example; dmarc=pass" }
    relay = { "name" => "Authentication-Results", "value" => "mx.cloudflare.net; dmarc=pass" }

    refute MailInbound::SenderAuthentication.authenticated?([ forged, relay ])
    refute MailInbound::SenderAuthentication.authenticated?(
      headers_from("evil.example; dmarc=pass")
    )
  end

  test "rejects dmarc fail, missing or unparsable headers" do
    refute MailInbound::SenderAuthentication.authenticated?(
      headers("mx.cloudflare.net; dkim=fail; dmarc=fail header.from=bank.example")
    )
    refute MailInbound::SenderAuthentication.authenticated?(headers)
    refute MailInbound::SenderAuthentication.authenticated?(nil)
  end

  private

  def headers(*values)
    headers_from(*values)
  end

  def headers_from(*values)
    [ { "name" => "From", "value" => "Banco <alertas@bank.example>" } ] +
      values.map { |value| { "name" => "Authentication-Results", "value" => value } }
  end
end
