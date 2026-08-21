# frozen_string_literal: true

class RecurringTransactionsController < ApplicationController
  before_action :set_categories, only: [ :index ]
  before_action :load_index_data, only: [ :index ]
  before_action :set_recurring_transaction, only: [ :update, :destroy, :process_transaction, :toggle_active ]

  def index
    @recurring_transaction ||= current_user.recurring_transactions.build(
      transaction_type: @transaction_type,
      active: true
    )
  end

  def create
    @recurring_transaction = current_user.recurring_transactions.build(recurring_transaction_params)

    if @recurring_transaction.save
      redirect_to recurring_transactions_path(type: @recurring_transaction.transaction_type),
                  notice: "Recurring #{@recurring_transaction.transaction_type} was successfully created."
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @recurring_transaction.update(update_params)
      redirect_to recurring_transactions_path(type: @recurring_transaction.transaction_type),
                  notice: "Recurring #{@recurring_transaction.transaction_type} was successfully updated."
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    type = @recurring_transaction.transaction_type
    @recurring_transaction.destroy
    redirect_to recurring_transactions_path(type: type),
                notice: "Recurring #{type} was successfully deleted."
  end

  # Receive (income) / Pay (expense): creates the real one-time transaction.
  def process_transaction
    result = RecurringTransactionProcessor.call(
      recurring_transaction: @recurring_transaction,
      amount: params[:amount],
      date: params[:date]
    )

    if result.success?
      redirect_to recurring_transactions_path(type: @recurring_transaction.transaction_type),
                  notice: "#{@recurring_transaction.action_label}ed #{number_to_currency(result.transaction.amount)} " \
                          "on #{result.transaction.date.strftime('%B %-d, %Y')}."
    else
      redirect_to recurring_transactions_path(type: @recurring_transaction.transaction_type),
                  alert: result.error,
                  status: :see_other
    end
  end

  # Soft-disable / re-enable without deleting the configuration.
  def toggle_active
    @recurring_transaction.update!(active: !@recurring_transaction.active?)
    state = @recurring_transaction.active? ? "activated" : "deactivated"
    redirect_to recurring_transactions_path(type: @recurring_transaction.transaction_type),
                notice: "Recurring #{@recurring_transaction.transaction_type} was successfully #{state}."
  end

  private

  def set_categories
    @categories = Category.all
  end

  def load_index_data
    @transaction_type = %w[income expense].include?(params[:type]) ? params[:type] : "income"
    @recurring_transactions = current_user.recurring_transactions
                                          .includes(:category, :occurrences)
                                          .of_type(@transaction_type)
                                          .ordered
    @current_period = Date.current.strftime("%Y-%m")
  end

  # Owner-only authorization: scoping through current_user guarantees a user
  # can never load another user's recurring transaction.
  def set_recurring_transaction
    @recurring_transaction = current_user.recurring_transactions.find(params[:id])
  end

  def recurring_transaction_params
    params.require(:recurring_transaction)
          .permit(:category_id, :transaction_type, :amount, :description, :payment_day, :active)
  end

  # The transaction type is immutable after creation so historical
  # occurrences stay consistent.
  def update_params
    params.require(:recurring_transaction)
          .permit(:category_id, :amount, :description, :payment_day, :active)
  end
end
