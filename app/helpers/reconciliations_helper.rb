# frozen_string_literal: true

module ReconciliationsHelper
  STATUS_STYLES = {
    "pending" => { dot: "text-danger", badge: "bg-danger-subtle text-danger", icon: "ti-circle-dot" },
    "warning" => { dot: "text-warning", badge: "bg-warning-subtle text-warning-emphasis", icon: "ti-circle-dot" },
    "reconciled" => { dot: "text-success", badge: "bg-success-subtle text-success", icon: "ti-circle-check" },
    "todo" => { dot: "text-warning", badge: "bg-warning-subtle text-warning-emphasis", icon: "ti-circle-dot" }
  }.freeze

  STATUS_PILLS = {
    "unverified" => { css: "todo", icon: nil, key: "unverified" },
    "ok" => { css: "done", icon: "ti-check", key: "ok" },
    "difference" => { css: "diff", icon: "ti-alert-circle", key: "difference" },
    "left_pending" => { css: "diff", icon: "ti-hourglass", key: "left_pending" }
  }.freeze

  DEBT_KINDS = %w[credit_card loan].freeze

  def reconciliation_status_badge(status, label)
    styles = STATUS_STYLES.fetch(status, STATUS_STYLES["todo"])
    tag.span(class: "badge rounded-pill d-inline-flex align-items-center gap-1 fw-semibold #{styles[:badge]}") do
      tag.i(class: "ti #{styles[:icon]} small") + tag.span(label)
    end
  end

  def reconciliation_status_pill(status)
    styles = STATUS_PILLS.fetch(status, STATUS_PILLS["unverified"])
    tag.span(class: "rec-status #{styles[:css]}") do
      safe_join([
        (tag.i(class: "ti #{styles[:icon]}") if styles[:icon]),
        tag.span(t("reconciliation.balances.statuses.#{styles[:key]}"))
      ].compact)
    end
  end

  def reconciliation_debt_balance?(balance)
    DEBT_KINDS.include?(balance["kind"])
  end

  def reconciliation_verified_balance?(balance)
    balance["status"] == "ok"
  end

  def reconciliation_balance_name(balance)
    balance["account_name"].presence || balance["name"]
  end

  def reconciliation_balance_label(balance)
    if reconciliation_debt_balance?(balance)
      t("reconciliation.balances.debt_balance", app_name: AppName.current)
    else
      t("reconciliation.balances.app_balance", app_name: AppName.current)
    end
  end

  def reconciliation_balance_kind_label(balance)
    if balance["kind"] == "loan" && balance["sub_kind"] == "revolving"
      t("reconciliation.balances.kinds.revolving")
    else
      t("reconciliation.balances.kinds.#{balance["kind"]}", default: balance["kind"].to_s.humanize)
    end
  end

  def reconciliation_balance_meta(balance)
    parts = [ reconciliation_balance_kind_label(balance) ]
    parts << "•• #{balance["identifier"]}" if balance["identifier"].present?
    parts << balance["institution_name"] if balance["institution_name"].present?
    parts.join(" · ")
  end

  def reconciliation_balance_action_label(balance)
    if reconciliation_verified_balance?(balance)
      t("reconciliation.balances.change_balance")
    else
      t("reconciliation.balances.reconcile")
    end
  end

  def reconciliation_payment_icon(payment)
    icon = payment["category_icon"].to_s.strip
    icon = "ti-tag" unless icon.match?(/\Ati-[a-z0-9-]+\z/)
    "ti #{icon}"
  end

  def reconciliation_progress_caption(state)
    return t("reconciliation.hero.progress_empty") if state.total_sources_count.zero?

    if state.verified_sources_count == state.total_sources_count
      t("reconciliation.hero.progress_done")
    else
      t("reconciliation.hero.progress_start")
    end
  end

  def reconciliation_modal_title(balance, mode)
    return t("reconciliation.reconcile.movements_title_mode") if mode == "movements"

    if reconciliation_debt_balance?(balance)
      t("reconciliation.reconcile.debt_title")
    else
      t("reconciliation.reconcile.title")
    end
  end

  def reconciliation_movements_title(balance)
    if reconciliation_debt_balance?(balance)
      t("reconciliation.reconcile.debt_movements_title")
    else
      t("reconciliation.reconcile.movements_title")
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
    I18n.l(date, format: "%-d %b")
  end
end
