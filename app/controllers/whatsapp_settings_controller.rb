# frozen_string_literal: true

# WhatsappSettingsController
# GET    /settings/whatsapp            : status card — connected phone,
#                                        "Connecting…" while a token is pending,
#                                        or the primary CONNECT token button
# GET    /settings/whatsapp/status     : lightweight JSON for frontend polling
# DELETE /settings/whatsapp/pending    : cancels the pending connect attempt
# DELETE /settings/whatsapp            : disconnects (keeps expenses + identity)
#
# The connect token is generated when the disconnected user opens the page
# (the flow initiation) and is REUSED on refresh until connected, cancelled or
# expired — polling never generates tokens.
class WhatsappSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    load_connection
    return if @connection

    # Fresh token for the primary button on every disconnected page view. The
    # "Connecting…" state is purely client-side (started by the button click):
    # a page refresh always lands back on the token button, never on a fake
    # in-progress state.
    @connect_code = PendingWhatsappConnection.generate_for!(current_user)
  end

  def status
    if active_connection
      render json: { status: "connected", phone_number: "+#{active_connection.whatsapp_identity.phone_number}" }
    elsif valid_pending
      render json: { status: "pending" }
    else
      render json: { status: "disconnected" }
    end
  end

  def cancel
    current_user.pending_whatsapp_connections.unused.where("expires_at > ?", Time.current)
                .find_each(&:consume!)
    head :ok
  end

  def destroy
    current_user.whatsapp_connections.active.last&.disconnect!
    redirect_to whatsapp_settings_path,
                notice: t("whatsapp.settings.disconnected", default: "WhatsApp desconectado. Tus gastos no se borraron.")
  end

  private

  private

  def load_connection
    @connection = current_user.whatsapp_connections.active.includes(:whatsapp_identity).order(:id).last
  end

  def active_connection
    current_user.whatsapp_connections.active.order(:id).last
  end

  def valid_pending
    current_user.pending_whatsapp_connections.unused.where("expires_at > ?", Time.current).order(:id).last
  end
end
