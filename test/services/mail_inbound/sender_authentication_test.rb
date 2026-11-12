# frozen_string_literal: true

require "test_helper"

class MailInbound::SenderAuthenticationTest < ActiveSupport::TestCase
  test "accepts a dkim pass" do
    assert MailInbound::SenderAuthentication.authenticated?(
      headers("mx.cloudflare.net; dkim=pass header.d=bank.example")
    )
  end

  test "accepts a dmarc pass" do
    assert MailInbound::SenderAuthentication.authenticated?(
      headers("mx.cloudflare.net; dmarc=pass action=none")
    )
  end

  test "rejects missing or failed results" do
    refute MailInbound::SenderAuthentication.authenticated?(
      headers("mx.cloudflare.net; dkim=fail header.d=bank.example")
    )
    refute MailInbound::SenderAuthentication.authenticated?(headers)
    refute MailInbound::SenderAuthentication.authenticated?(nil)
  end

  private

  def headers(*values)
    [ { "name" => "From", "value" => "Banco <alertas@bank.example>" } ] +
      values.map { |value| { "name" => "Authentication-Results", "value" => value } }
  end
end
