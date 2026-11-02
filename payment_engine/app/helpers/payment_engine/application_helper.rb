# frozen_string_literal: true

module PaymentEngine
  module ApplicationHelper
    def status_badge(status)
      cls = case status.to_s
            when "active", "succeeded", "processed", "paid" then "pe-badge-success"
            when "failed", "cancelled", "expired" then "pe-badge-danger"
            when "pending", "suspended", "paused" then "pe-badge-warning"
            else "pe-badge-neutral"
            end
      "<span class=\"pe-badge #{cls}\">#{status}</span>".html_safe
    end
  end
end
