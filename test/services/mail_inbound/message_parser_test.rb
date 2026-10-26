# frozen_string_literal: true

require "test_helper"

class MailInbound::MessageParserTest < ActiveSupport::TestCase
  RECIPIENT = "receive+user1@samyreplies.com"

  def raw_email(message_id: "<inbound-1@example.com>", text: "Compra aprobada por $48.500", html: nil, attachment: false)
    mail = Mail.new
    mail.from = "Banco <notificaciones@bank.example>"
    mail.to = RECIPIENT
    mail.subject = "Compra aprobada"
    mail.message_id = message_id if message_id
    mail.text_part = Mail::Part.new do
      content_type "text/plain; charset=UTF-8"
      body text
    end
    if html
      mail.html_part = Mail::Part.new do
        content_type "text/html; charset=UTF-8"
        body html
      end
    end
    mail.add_file(filename: "receipt.pdf", content: "%PDF-1.4 test") if attachment
    mail.to_s
  end

  def parse(raw, envelope_to: RECIPIENT)
    MailInbound::MessageParser.call(raw, envelope_from: "envelope@bank.example", envelope_to: envelope_to)
  end

  test "parses sender, recipient, subject, text and headers" do
    message = parse(raw_email)

    assert_includes message[:from], "notificaciones@bank.example"
    assert_equal [ RECIPIENT ], message[:to]
    assert_equal "Compra aprobada", message[:subject]
    assert_includes message[:body_text], "Compra aprobada por $48.500"
    assert_kind_of Time, message[:internal_date]
  end

  test "parses HTML and attachment metadata" do
    message = parse(raw_email(html: "<p>Compra <strong>aprobada</strong></p>", attachment: true))

    assert_equal "<p>Compra <strong>aprobada</strong></p>", message[:html]
    assert_equal 1, message[:attachments].size
    assert_equal "receipt.pdf", message[:attachments].first["filename"]
  end

  test "uses a deterministic body hash when Message-ID is missing" do
    raw = raw_email(message_id: nil).sub(/^Message-ID:.*\r?\n/, "")

    first = parse(raw)
    second = parse(raw)

    assert_match(/\Asha256:[0-9a-f]{64}\z/, first[:id])
    assert_equal first[:id], second[:id]
  end

  test "rejects an empty message" do
    assert_raises(MailInbound::MessageParser::Error) { parse("") }
  end
end
