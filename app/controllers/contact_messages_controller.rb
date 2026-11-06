# frozen_string_literal: true

# ContactMessagesController
# Receives the public Contáctanos form. The message is validated, deduplicated
# and delivered by email; it is not persisted in the database.
#
# Example:
#   POST /contact
#   { contact_message: { name: "Ana", email: "ana@example.com",
#                        subject: "Soporte", message: "Hola" } }
class ContactMessagesController < ApplicationController
  skip_before_action :authenticate_user!, only: :create
  skip_before_action :require_membership_selection, only: :create

  RATE_LIMIT = 5
  RATE_LIMIT_WINDOW = 10.minutes
  DUPLICATE_TTL = 2.minutes

  # Keyed by IP so a bot cannot flood the internal inbox. The limit is applied
  # before the action, including submissions that later fail validation.
  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, only: :create,
             store: RateLimitProxy.new, name: "contact",
             with: :respond_rate_limited

  def create
    @contact_message = ContactMessage.new(contact_message_params)

    # Honeypot: answer with a generic success so bots do not learn the rule.
    return respond_success if @contact_message.spam?
    return respond_invalid unless @contact_message.valid?
    return respond_success if duplicate_submission?

    remember_submission
    ContactMailer.with(@contact_message.delivery_params).new_message.deliver_later

    respond_success
  end

  private

  def contact_message_params
    source = params[:contact_message]
    return {} unless source.respond_to?(:permit)

    source.permit(:name, :email, :subject, :message, :website)
  end

  def respond_success
    respond_to do |format|
      format.json { render json: { ok: true }, status: :ok }
      format.html { redirect_to "/contact?sent=1", status: :see_other }
    end
  end

  def respond_invalid
    respond_to do |format|
      format.json do
        render json: {
          ok: false,
          error: I18n.t("contact.errors.invalid"),
          errors: @contact_message.errors.to_hash
        }, status: :unprocessable_entity
      end
      format.html { redirect_to "/contact?error=1", status: :see_other }
    end
  end

  def respond_rate_limited
    respond_to do |format|
      format.json do
        render json: { ok: false, error: I18n.t("contact.errors.rate_limited") },
               status: :too_many_requests
      end
      format.html do
        redirect_to "/contact?error=1", status: :see_other,
                    alert: I18n.t("contact.errors.rate_limited")
      end
    end
  end

  def duplicate_submission?
    Rails.cache.exist?(duplicate_key)
  end

  def remember_submission
    Rails.cache.write(duplicate_key, true, expires_in: DUPLICATE_TTL)
  end

  def duplicate_key
    fingerprint = [
      request.remote_ip,
      @contact_message.email,
      @contact_message.subject,
      @contact_message.message
    ].join("\0")

    "contact-form:dedupe:#{Digest::SHA256.hexdigest(fingerprint)}"
  end
end
