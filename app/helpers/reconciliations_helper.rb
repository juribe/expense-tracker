# frozen_string_literal: true

module ReconciliationsHelper
  STATUS_STYLES = {
    "pending" => { dot: "text-danger", badge: "bg-danger-subtle text-danger", icon: "bi-circle-fill" },
    "warning" => { dot: "text-warning", badge: "bg-warning-subtle text-warning-emphasis", icon: "bi-circle-fill" },
    "reconciled" => { dot: "text-success", badge: "bg-success-subtle text-success", icon: "bi-check-circle-fill" },
    # Row-level statuses
    "unverified" => { dot: "text-secondary", badge: "bg-secondary-subtle text-secondary-emphasis", icon: "bi-circle" },
    "difference" => { dot: "text-warning", badge: "bg-warning-subtle text-warning-emphasis", icon: "bi-exclamation-circle-fill" },
    "left_pending" => { dot: "text-warning", badge: "bg-warning-subtle text-warning-emphasis", icon: "bi-hourglass-split" },
    "ok" => { dot: "text-success", badge: "bg-success-subtle text-success", icon: "bi-check-circle-fill" }
  }.freeze

  def reconciliation_status_badge(status, label)
    styles = STATUS_STYLES.fetch(status, STATUS_STYLES["unverified"])
    tag.span(class: "badge rounded-pill d-inline-flex align-items-center gap-1 fw-semibold #{styles[:badge]}") do
      tag.i(class: "bi #{styles[:icon]} small") + tag.span(label)
    end
  end

  def reconciliation_money(value)
    number_to_currency(value.to_d)
  end

  def reconciliation_signed_money(value)
    decimal = value.to_d
    prefix = decimal.positive? ? "+" : ""
    "#{prefix}#{number_to_currency(decimal.abs)}"
  end

  # "Hoy, 2:34 PM" when the check happened today, otherwise a short date.
  def reconciliation_checked_at_label(iso)
    return nil if iso.blank?

    time = Time.zone.parse(iso)
    return nil if time.nil?

    if time.today?
      t("reconciliation.checked_today", time: time.strftime("%-I:%M %p"))
    else
      t("reconciliation.checked_on", date: I18n.l(time.to_date, format: :short))
    end
  end

  def reconciliation_due_date_label(iso)
    return nil if iso.blank?

    date = Date.parse(iso)
    I18n.l(date, format: "%b %-d")
  end

  def reconciliation_movement_kind_label(kind)
    kind == "income" ? t("reconciliation.movements.income") : t("reconciliation.movements.expense")
  end
end
