# frozen_string_literal: true

class PlansController < ApplicationController
  before_action :authenticate_user!
  REUSE_WINDOW_MINUTES = 45

  def index
    @monthly = PaymentEngine::PaymentOption.find_by(name: "Mensual")
    @annual = PaymentEngine::PaymentOption.find_by(name: "Anual")
    @can_trial = PaymentEngine::AccessPolicy.can_start_trial?(current_user)
    @settings = PaymentEngine::Setting.current
    if session[:pending_payment_option_id].present?
      @selected_option = PaymentEngine::PaymentOption.find_by(id: session[:pending_payment_option_id])
    end

    # After an ePayco response redirect, send the user to the dedicated
    # checkout result page and drop the pending checkout session so the
    # payment modal does not open again.
    if params[:ref_payco].present?
      session.delete(:pending_checkout)
      redirect_to checkout_result_plans_path(ref_payco: params[:ref_payco]) and return
    end
  end

  def start_trial
    result = PaymentEngine::Memberships::StartFreeTrial.call(owner: current_user, actor: current_user)
    if result.success?
      session.delete(:trial_intent)
      session.delete(:pending_payment_option_id)
      session.delete(:requires_membership)
      current_user.update!(requires_membership: false) if current_user.respond_to?(:requires_membership=)
      redirect_to root_path, notice: "Tu prueba gratuita ha comenzado."
    else
      redirect_to plans_path, alert: result.errors.join(", ")
    end
  end

  def checkout
    @option = PaymentEngine::PaymentOption.find(params[:payment_option_id])
    @settings = PaymentEngine::Setting.current
  rescue ActiveRecord::RecordNotFound
    redirect_to plans_path, alert: "Opción no disponible."
  end

  def checkout_result
    @ref_payco = params[:ref_payco].presence
    purchase = PaymentEngine::Purchase.find_by(id: session[:pending_purchase_id])
    @purchase_status = purchase&.status || "unknown"
  end

  def checkout_status
    ref = params[:ref_payco].presence
    purchase = PaymentEngine::Purchase.find_by(id: session[:pending_purchase_id]) ||
               PaymentEngine::Purchase.where(owner: current_user).order(created_at: :desc).first

    if ref.present? && purchase
      result = PaymentEngine::Payments::Verify.call(
        provider: "epayco",
        reference: ref,
        purchase: purchase,
        payment: purchase.payment
      )
      if result.success?
        render json: { status: result.data[:state], ref_payco: ref, purchase_id: purchase.id }
        return
      end
    end

    render json: { status: purchase&.status || "unknown", ref_payco: ref, purchase_id: purchase&.id }
  end

  def create_checkout
    option = PaymentEngine::PaymentOption.find(params[:payment_option_id])
    unless PaymentEngine::Configuration.payments_enabled?
      redirect_to plans_path, alert: "Los pagos están deshabilitados." and return
    end
    unless option.status == "active"
      redirect_to plans_path, alert: "La opción ya no está disponible." and return
    end

    purchase, payment = find_or_build_purchase(option: option)

    session.delete(:pending_payment_option_id)
    session[:pending_purchase_id] = purchase.id

    # Start provider checkout when ePayco is configured. This keeps the host
    # application agnostic of ePayco internals while using the common contract.
    start_checkout(purchase: purchase, payment: payment, option: option)
  rescue StandardError => e
    redirect_to plans_path, alert: e.message
  end

  def start_checkout(purchase:, payment:, option:)
    return redirect_to plans_path, notice: "Compra iniciada. Completa el pago para activar tu membresía." unless PaymentEngine.provider_settings_for(:epayco).present? || PaymentEngine.configuration.default_provider == :epayco

    provider_settings = PaymentEngine.provider_settings_for(:epayco)
    # ePayco requires absolute HTTPS urls for response/confirmation. Prefer
    # a configured public base url, fall back to the request host.
    public_base = provider_settings[:public_base_url].presence ||
                  ENV["EPAYCO_WEBHOOK_BASE_URL"].presence ||
                  request.base_url
    confirmation_url = provider_settings[:confirmation_url].presence || "#{public_base}/payment_engine/webhooks/epayco"
    return_url = provider_settings[:response_url].presence || "#{public_base}/plans"

    begin
      provider = PaymentEngine.provider(:epayco)
      result = provider.create_payment(
        purchase: purchase,
        payment: payment,
        return_url: return_url,
        confirmation_url: confirmation_url,
        customer_ip: request.respond_to?(:remote_ip) ? request.remote_ip : nil
      )
      if result.success?
        checkout = result.data.is_a?(Hash) ? (result.data[:checkout] || result.data["checkout"]) : nil
        url = checkout.is_a?(Hash) ? (checkout[:url] || checkout["url"] || checkout[:payment_url] || checkout["payment_url"]) : nil
        if url.present?
          redirect_to url, allow_other_host: true and return
        else
          # ePayco sessions return { sessionId, token }. The host opens the
          # Smart Checkout with its own JS module and that id.
          session[:pending_checkout] = checkout
          redirect_to plans_path, notice: "Abriendo el checkout de pago..." and return
        end
      else
        redirect_to plans_path, alert: "No se pudo iniciar el pago: #{result.errors.join(', ')}"
      end
    rescue StandardError => e
      redirect_to plans_path, alert: "Error al iniciar el pago: #{e.message}"
    end
  end

  def find_or_build_purchase(option:)
    # Avoid double payments: if this user has a pending purchase for the same
    # option that has not reached the provider yet, reuse it.
    recent_pending = PaymentEngine::Purchase
      .pending_or_processing
      .where(owner: current_user, payment_option: option)
      .where("created_at >= ?", REUSE_WINDOW_MINUTES.minutes.ago)
      .order(created_at: :desc)
      .first

    if recent_pending && recent_pending.payment&.external_reference.blank?
      payment = recent_pending.payment
      return [ recent_pending, payment ] if payment

      payment = PaymentEngine::Payment.create!(
        purchase: recent_pending,
        amount: option.price,
        currency: option.currency,
        status: "pending",
        payment_method: params[:method].presence || "card",
        provider_code: "epayco"
      )
      recent_pending.update!(payment: payment)
      return [ recent_pending, payment ]
    end

    purchase = nil
    ActiveRecord::Base.transaction do
      purchase = PaymentEngine::Purchase.create!(
        owner: current_user,
        payment_option: option,
        amount: option.price,
        currency: option.currency,
        status: "pending",
        commercial_snapshot: {
          "name" => option.name,
          "price" => option.price.to_s,
          "currency" => option.currency,
          "mode" => option.mode
        }
      )
      payment = PaymentEngine::Payment.create!(
        purchase: purchase,
        amount: option.price,
        currency: option.currency,
        status: "pending",
        payment_method: params[:method].presence || "card",
        provider_code: "epayco"
      )
      purchase.update!(payment: payment)
    end
    [ purchase, purchase.payment ]
  end
end
