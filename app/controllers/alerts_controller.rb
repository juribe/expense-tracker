# frozen_string_literal: true

# AlertsController
# RESTful for SpendingAlert: lists the user's notification center (grouped by
# month, filterable), marks a single alert read (Turbo) and marks all read.
class AlertsController < ApplicationController
  before_action :authenticate_user!

  def index
    @filter = params[:filter].to_s
    @alerts = filtered_alerts.includes(:category).order(created_at: :desc)
    @unread_count = current_user.spending_alerts.unread.count
  end

  # PATCH /alerts/:id — marks a single alert as read via Turbo.
  def update
    alert = current_user.spending_alerts.find(params[:id])
    alert.update!(read_at: Time.current)
    render turbo_stream: turbo_stream.replace(dom_id(alert), alert_row(alert))
  end

  # PATCH /alerts/mark_all_read
  def mark_all_read
    current_user.spending_alerts.unread.update_all(read_at: Time.current)
    redirect_to alerts_path, notice: t("alerts.marked_all_read", default: "Alertas marcadas como leídas")
  end

  private

  def filtered_alerts
    relation = current_user.spending_alerts
    case @filter
    when "unread" then relation.unread
    when "budget" then relation.budget
    when "spending" then relation.spending
    else relation.all
    end
  end

  def alert_row(alert)
    render_to_string(partial: "alerts/alert", locals: { alert: alert })
  end
end