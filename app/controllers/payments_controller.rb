# frozen_string_literal: true

# PaymentsController
# Nested /money_sources/:money_source_id/payments for a user's debt sources.
# Applies an existing Expense to that debt with a manually entered
# distribution (principal, interest, insurance, other); no file import.
class PaymentsController < ApplicationController
  include ActionView::Helpers::NumberHelper

  before_action :authenticate_user!
  before_action :set_money_source
  before_action :set_payment, only: [ :edit, :update, :destroy ]
  before_action :set_expense, only: [ :new, :create ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def new
    @payment = Payment.new(amount: @expense.amount.to_d.abs, principal_amount: @expense.amount.to_d.abs)
  end

  # GET /money_sources/:money_source_id/payments/manual
  # Blank form to create a payment from scratch: it creates the expense AND
  # applies it to the debt (like the statement import's payment).
  def manual
    load_manual_form_data
  end

  def edit
    @expense = @payment.expense
  end

  def create
    result = Payments::Apply.call(user: current_user, money_source: @money_source,
                                  expense: @expense, distribution: payment_params)

    if result.success?
      redirect_to money_source_path(@money_source),
                  notice: t("payments.created", amount: number_to_currency(@expense.amount.to_d.abs),
                                                       target: @money_source.name)
    else
      @payment = Payment.new(payment_params)
      flash.now[:alert] = result.errors.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  # POST /money_sources/:money_source_id/payments/create_manual
  # Creates the expense and applies the payment in one step (like the import).
  # A plain request redirects; an AJAX request gets a redirect URL (or errors)
  # as JSON so the modal can show failures inline.
  def create_manual
    attributes = manual_payment_params
    result = Payments::CreateManual.call(
      user: current_user,
      money_source: @money_source,
      amount: attributes[:amount],
      date: attributes[:date],
      description: attributes[:description],
      category_id: attributes[:category_id],
      funding_money_source_id: attributes[:funding_money_source_id],
      idempotency_key: attributes[:idempotency_key],
      distribution: attributes.slice(:principal_amount, :interest_amount, :insurance_amount, :other_amount)
    )

    if result.success?
      notice = t("payments.created", amount: number_to_currency(result.result.amount),
                                      target: @money_source.name)
      respond_to do |format|
        format.html { redirect_to money_source_path(@money_source), notice: notice }
        format.json { render json: { ok: true, redirect_url: money_source_path(@money_source) } }
      end
    else
      respond_to do |format|
        format.html { redirect_to money_source_path(@money_source), alert: result.errors.to_sentence }
        format.json { render json: { ok: false, errors: result.errors }, status: :unprocessable_entity }
      end
    end
  end

  def update
    result = Payments::Apply.call(user: current_user, money_source: @money_source,
                                  expense: @expense, distribution: payment_params,
                                  payment: @payment)

    if result.success?
      redirect_to money_source_path(@money_source), notice: t("payments.updated")
    else
      @payment.assign_attributes(payment_params)
      @expense = @payment.expense
      flash.now[:alert] = result.errors.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # A payment that created its expense reverts everything: destroying the
    # expense cascades into this payment (Transaction has_many :payments,
    # dependent: :destroy) and the Transaction callbacks restore the funding
    # source's balance, re-sync the recurring template and invalidate the
    # reconciliation. Payments over pre-existing expenses keep the expense.
    if @payment.created_expense?
      @payment.expense.destroy
    else
      @payment.destroy
    end
    redirect_to money_source_path(@money_source), notice: t("payments.deleted")
  end

  private

  def set_money_source
    @money_source = current_user.money_sources.find(params[:money_source_id])
  end

  def set_payment
    @payment = @money_source.payments.find(params[:id])
  end

  # The expense id arrives as a top-level param (GET /payments/new?expense_id=)
  # or inside the payment form payload (POST, hidden field payment[expense_id]).
  def set_expense
    @expense = current_user.expenses.find_by(id: params[:expense_id] || params.dig(:payment, :expense_id))
    return unless @expense.nil?

    redirect_apply_error(t("payments.not_found"))
  end

  def payment_params
    params.require(:payment).permit(:expense_id, :principal_amount, :interest_amount,
                                    :insurance_amount, :other_amount)
  end

  # The manual payment form posts everything under payment[]: the expense
  # fields (amount, date, description, category, funding source) plus the
  # distribution components the payment is split into.
  def manual_payment_params
    params.require(:payment).permit(:amount, :date, :description, :category_id,
                                    :funding_money_source_id, :idempotency_key,
                                    :principal_amount, :interest_amount,
                                    :insurance_amount, :other_amount)
  end

  def load_manual_form_data
    @payment = Payment.new
    @categories = Category.for_user(current_user).order(:name)
    @funding_sources = MoneySource.payment_origins(current_user).where.not(id: @money_source.id)
  end

  def redirect_apply_error(message)
    redirect_to money_source_path(@money_source), alert: message
  end

  def not_found
    head :not_found
  end
end
