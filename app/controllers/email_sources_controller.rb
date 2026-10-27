# frozen_string_literal: true

class EmailSourcesController < ApplicationController
  before_action :authenticate_user!

  def index
    @forwarding_address = current_user.forwarding_address
    @gmail_connections = current_user.gmail_connections.order(:created_at, :id)
    @email_sources = current_user.email_sources.order(:created_at, :id)
    @verifications = current_user.email_forwarding_verifications.active.order(created_at: :desc)
    @active_redirect_count = @email_sources.count(&:active?) + @gmail_connections.count(&:active?)
    # Initial recognition is done once a payment source has at least one
    # CONFIRMED identifier. Persisted suggestions never count (same rule as
    # MoneySource#recognition_configured?), only the review/accept step does.
    @recognition_configured = current_user.money_sources.payment_sources
                                           .joins(:recognition_identifiers)
                                           .merge(MoneySourceRecognitionIdentifier.confirmed)
                                           .exists?
  end

  def create
    source = current_user.email_sources.create!(
      source_type: params[:source_type].presence || "forwarding",
      email: params[:email].presence,
      status: "pending_setup"
    )
    redirect_to email_sources_path, notice: t("email_sources.created", default: "Fuente agregada.")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to email_sources_path, alert: e.message
  end

  def destroy
    source = current_user.email_sources.find(params[:id])
    source.destroy!
    redirect_to email_sources_path, notice: t("email_sources.removed", default: "Fuente eliminada.")
  end

  def confirm
    source = current_user.email_sources.find(params[:id])
    source.mark_active!

    respond_to do |format|
      format.html { redirect_to email_sources_path, notice: t("email_sources.confirmed", default: "Configuración confirmada.") }
      format.json { render json: { ok: true, source: source_payload(source) } }
    end
  end

  def retry
    source = current_user.email_sources.find(params[:id])
    source.update!(status: "pending_verification")
    redirect_to email_sources_path, notice: t("email_sources.retry", default: "Reintento iniciado.")
  end

  def connect_gmail
    redirect_to start_gmail_auth_path
  end

  def setup_status
    verification = current_user.email_forwarding_verifications.active.order(created_at: :desc).first
    pending_source = current_user.email_sources.forwarding.pending.order(created_at: :desc).first

    payload =
      if verification
        {
          state: "verification_email_detected",
          checked_at: Time.current.iso8601,
          verification: {
            id: verification.id,
            sender: verification.detected_sender,
            provider: "Gmail",
            subject: verification.subject,
            received_at: verification.created_at.strftime("%d/%m/%Y %H:%M"),
            url: verification.safe_confirmation_url
          }
        }
      elsif pending_source
        {
          state: "forwarding_email_detected",
          checked_at: Time.current.iso8601,
          source: source_payload(pending_source)
        }
      else
        { state: "waiting_for_email", checked_at: Time.current.iso8601 }
      end

    render json: payload
  end

  def confirm_verification
    verification = current_user.email_forwarding_verifications.find(params[:id])
    if verification.expired?
      respond_to do |format|
        format.html { redirect_to email_sources_path, alert: t("email_sources.verification_expired", default: "La verificación ha expirado.") }
        format.json { render json: { ok: false, error: "expired" }, status: :unprocessable_entity }
      end
      return
    end

    subject_email = EmailForwardingVerification.origin_email_from_subject(verification.subject)
    origin_email = subject_email || verification.detected_sender
    source = current_user.email_sources.forwarding.where("LOWER(email) = ?", subject_email.downcase).first if subject_email.present?
    linked_source = verification.email_source
    # Never activate a linked source for a different address; the subject names
    # the mailbox the verification belongs to.
    source ||= linked_source if linked_source && (subject_email.blank? || linked_source.email.blank? || linked_source.email.casecmp?(subject_email))

    if source.nil?
      source = current_user.email_sources.create!(
        source_type: "forwarding",
        email: origin_email,
        status: "pending_verification"
      )
    elsif source.email.blank? && origin_email.present?
      source.update!(email: origin_email)
    end

    verification.update!(email_source: source) unless verification.email_source_id == source.id
    source.mark_active!
    verification.consume!
    respond_to do |format|
      format.html { redirect_to email_sources_path, notice: t("email_sources.verified", default: "Configuración confirmada. El reenvío está activo.") }
      format.json { render json: { ok: true, source: source_payload(source) } }
    end
  end

  private

  def source_payload(source)
    {
      id: source.id,
      email: source.email,
      status: source.status,
      received_at: source.created_at.strftime("%d/%m/%Y %H:%M")
    }
  end
end
