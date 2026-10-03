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
    @payment.destroy
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
    params.require(:payment).permit(:principal_amount, :interest_amount,
                                    :insurance_amount, :other_amount)
  end

  def redirect_apply_error(message)
    redirect_to money_source_path(@money_source), alert: message
  end

  def not_found
    head :not_found
  end
end
