# frozen_string_literal: true

class GmailConnectionsController < ApplicationController
  before_action :set_connection, only: %i[update destroy sync sync_status]

  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  rescue_from Gmail::OauthClient::Error do |exception|
    redirect_to gmail_connection_path, alert: t("gmail_messages.oauth_error", message: exception.message)
  end

  def index
    @connection = current_user.gmail_connections.order(:id).last
    @configured = Gmail::OauthClient.configured?
    @pending_reviews = current_user.processed_emails.gmail.needs_review.order(created_at: :desc)
    @recent_imports = current_user.expenses.where(source: "gmail").order(date: :desc).limit(10)
    @polling_interval = GmailSyncJob.polling_interval_minutes
  end

  # Kicks off the Google OAuth authorization-code flow.
  def start_auth
    unless Gmail::OauthClient.configured?
      return redirect_to gmail_connection_path,
                         alert: t("gmail.oauth_missing")
    end

    # Recognition configuration is NOT required before connecting Gmail: the
    # first sync exists precisely to discover suggested senders/subjects/
    # keywords from the mailbox. Sources are needed so discovery has
    # something to attach the suggestions to.
    unless current_user.money_sources.exists?
      return redirect_to money_sources_recognition_path,
                         alert: t("money_sources.recognition.gmail_blocked")
    end

    state = SecureRandom.hex(16)
    session[:gmail_oauth_state] = state

    redirect_to Gmail::OauthClient.authorize_url(redirect_uri: google_callback_url, state: state),
                allow_other_host: true
  end

  def callback
    return oauth_failed(t("gmail_messages.invalid_state")) unless valid_state?

    tokens = Gmail::OauthClient.exchange_code(code: params[:code], redirect_uri: google_callback_url)
    info = Gmail::OauthClient.userinfo(tokens[:access_token])
    raise Gmail::OauthClient::Error, "Google did not return an email address" if info[:email].blank?

    connection = current_user.gmail_connections.find_or_initialize_by(email: info[:email])
    connection.google_account_id = info[:sub]
    connection.access_token = tokens[:access_token]
    connection.refresh_token = tokens[:refresh_token] if tokens[:refresh_token].present?
    connection.token_expires_at = tokens[:expires_at]
    connection.active = true
    connection.save!

    session.delete(:gmail_oauth_state)
    redirect_to gmail_connection_path, notice: t("gmail_messages.connected", email: info[:email])
  end

  def update
    @connection.update!(search_config: search_config_params)
    redirect_to gmail_connection_path, notice: t("gmail_messages.criteria_updated")
  end

  def destroy
    email = @connection.email
    @connection.destroy!
    redirect_to gmail_connection_path, notice: t("gmail_messages.disconnected", email: email)
  end
  # Kicks off the Gmail synchronization in the background. Enqueues a job
  # instead of running Gmail::SyncService synchronously, because a full sync
  # (fetch + AI extraction + recognition discovery for up to 25 messages) can
  # take a while — the request should return immediately and let the user keep
  # browsing. Results appear once the job finishes (refresh the page).
  def sync
    GmailSyncJob.perform_later(connection_id: @connection.id)
    redirect_to gmail_connection_path, notice: t("gmail_messages.sync_started")
  end

  # JSON endpoint polled by the Gmail settings page while a sync is running.
  # Returns { syncing: bool, summary: {...} } so the front-end can auto-refresh.
  def sync_status
    summary = @connection.last_sync_summary
    render json: {
      syncing: @connection.syncing.present?,
      summary: summary,
      last_synced_at: @connection.last_synced_at&.iso8601
    }
  end

  # Approves a low-confidence transaction extracted from an email.
  def approve
    review = current_user.processed_emails.gmail.needs_review.find(params[:id])
    expense_ids = create_expenses_from_review(review)

    review.update!(status: "processed", expense_id: expense_ids.first, failure_reason: nil,
                   processed_at: Time.current)
    redirect_to gmail_connection_path, notice: t("gmail_messages.expenses_created", count: expense_ids.size)
  end

  # Discards a reviewed transaction without creating expenses.
  def reject
    review = current_user.processed_emails.gmail.needs_review.find(params[:id])
    review.update!(status: "ignored", failure_reason: "rejected by user", processed_at: Time.current)
    redirect_to gmail_connection_path, notice: t("gmail_messages.transaction_discarded")
  end

  private

  def set_connection
    @connection = current_user.gmail_connections.find_by(id: params[:id]) ||
                  current_user.gmail_connections.order(:id).last
    return if @connection

    redirect_to gmail_connection_path, alert: t("gmail_messages.no_connection")
  end

  def valid_state?
    expected = session[:gmail_oauth_state].presence
    provided = params[:state].presence
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected.to_s, provided.to_s)
  end

  def oauth_failed(message)
    redirect_to gmail_connection_path, alert: message
  end

  def search_config_params
    raw = params.fetch(:search_config, {}).permit(:senders, :domains, :subject_keywords)
    {
      senders: split_values(raw[:senders]),
      domains: split_values(raw[:domains]),
      subject_keywords: split_values(raw[:subject_keywords])
    }
  end

  def split_values(value)
    value.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?).uniq
  end

  def create_expenses_from_review(review)
    transactions = review.payload_data["transactions"] || []
    transactions.filter_map do |transaction|
      next unless transaction["type"] == "expense"

      matched = MoneySources::Match.call(
        user: current_user,
        card_last_four: transaction["card_last_four"],
        bank: transaction["bank"]
      )
      # Match returns an array when several sources share the tag. Do not
      # auto-assign: leave the expense without a source for manual review.
      money_source = matched if matched.is_a?(MoneySource)

      Expenses::Create.call(
        user: current_user,
        amount: transaction["amount"],
        description: transaction["merchant"],
        category: transaction["category"],
        occurred_at: Time.zone.parse(transaction["occurred_at"].to_s) || Time.current,
        source: :gmail,
        gmail_message_id: review.message_id,
        money_source: money_source
      ).id
    end
  end
end
