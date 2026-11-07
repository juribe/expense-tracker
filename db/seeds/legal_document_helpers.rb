# frozen_string_literal: true

# Shared block builders for the Maglev legal documents (privacy policy and
# terms and conditions).
module LegalDocumentHelpers
  def text(html)
    { type: "privacy_text", text: html }
  end

  def list(items, ordered: false)
    { type: "privacy_list", ordered: ordered, items: items }
  end

  def cards(items, columns: "two")
    { type: "privacy_cards", columns: columns, items: items }
  end

  def card(icon:, title:, text:)
    { icon: icon, title: title, text: text }
  end

  def callout(title, text, variant = "note")
    { type: "privacy_callout", title: title, text: text, variant: variant }
  end

  def providers(items)
    { type: "privacy_providers", items: items }
  end

  def provider(name:, service_type:, purpose:, data:, policy_url: "")
    {
      name: name,
      service_type: service_type,
      purpose: purpose,
      data: data,
      policy_url: policy_url
    }
  end

  def section(anchor:, title:, nav_label: nil, intro: nil, number: nil, children: [])
    {
      anchor: anchor,
      title: title,
      nav_label: nav_label,
      intro: intro,
      number: number,
      children: children
    }
  end
end
