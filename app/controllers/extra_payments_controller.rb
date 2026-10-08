# frozen_string_literal: true

# ExtraPaymentsController
# REAL extraordinary payments on a user's loan money source: POST applies
# the payment (cash expense from a funding source + principal-only payment
# to the debt); DELETE reverts it via discard!. Nested under
# /money_sources/:money_source_id/extra_payments.
class ExtraPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_money_source
  before_action :set_extra_payment, only: [ :destroy ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def create
    funding = current_user.money_sources.payment_sources.find_by(id: params[:funding_money_source_id])
    result = Credits::ExtraPayments::Create.call(money_source: @money_source,
                                                 funding_money_source: funding,
                                                 date: params[:date],
                                                 amount: params[:extra_amount],
                                                 application_type: params[:application_type],
                                                 note: params[:note])
    if result.success?
      redirect_to money_source_path(@money_source), notice: t("credits.extras.recorded")
    else
      redirect_to money_source_path(@money_source), alert: result.errors.to_sentence
    end
  end

  def destroy
    @extra_payment.discard!
    redirect_to money_source_path(@money_source), notice: t("credits.extras.deleted")
  end

  private

  def set_money_source
    @money_source = current_user.money_sources.find(params[:money_source_id])
  end

  def set_extra_payment
    @extra_payment = @money_source.credit_extra_payments.find(params[:extra_id])
  end

  def not_found
    head :not_found
  end
end
