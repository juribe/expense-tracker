# frozen_string_literal: true

# StatementImportsController
# Nested /money_sources/:money_source_id/statement_imports — brings a parsed
# credit-card / loan statement into the apply-payment flow of that debt.
# Upload (file + optional password) → review (summary totals, movements
# compared against existing expenses, prefilled payment distribution) →
# confirm (creates the selected expenses and, optionally, the payment).
# Nothing is written until confirm.
class StatementImportsController < ApplicationController
  include ActionView::Helpers::NumberHelper

  before_action :authenticate_user!
  before_action :set_money_source
  before_action :ensure_debt_source

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /money_sources/:money_source_id/statement_imports/new
  def new
  end

  # POST — parses the upload and renders the review; never persists.
  def create
    result = Statements::Parser.call(user: current_user, file_data: file_data,
                                     filename: upload_filename, password: params[:password])

    unless result.success?
      redirect_to new_money_source_statement_import_path(@money_source),
                  alert: t("statement_imports.parse_failed", error: result.errors.to_sentence)
      return
    end

    @review = Statements::ReviewBuilder.call(user: current_user, document: result.result,
                                             money_source: @money_source)
    render :review
  end

  # POST /money_sources/:money_source_id/statement_imports/confirm — persists
  # the reviewed rows and payment; on failure the review is re-rendered from
  # the posted data without anything created.
  def confirm
    result = Statements::Confirmation.call(user: current_user, money_source: @money_source,
                                           movements: movement_rows, payment: payment_params)

    if result.success?
      redirect_to money_source_path(@money_source), notice: confirmation_notice(result.result)
    else
      @review = rebuild_review
      flash.now[:alert] = result.errors.to_sentence
      render :review, status: :unprocessable_entity
    end
  end

  private

  def set_money_source
    @money_source = current_user.money_sources.find(params[:money_source_id])
  end

  def ensure_debt_source
    return if @money_source.debt?

    redirect_to money_source_path(@money_source), alert: t("statement_imports.unsupported_target")
  end

  # The browser sends a real multipart file; the pipeline consumes a base64
  # data URI, so the upload is decoded here and used in memory only.
  def file_data
    upload = params[:file]
    return if upload.blank?

    content = upload.respond_to?(:read) ? upload.read : upload.to_s
    mime = upload.respond_to?(:content_type) ? upload.content_type : "application/octet-stream"
    "data:#{mime};base64,#{Base64.strict_encode64(content)}"
  end

  def upload_filename
    params[:filename].presence ||
      (params[:file].original_filename if params[:file].respond_to?(:original_filename))
  end

  # The form submits indexed rows (movements[0][description], …) which Rails
  # parses into an indexed hash, not an array. Keep both shapes and preserve
  # the declared order; unchecked rows keep their hidden fields but no
  # selected flag.
  def movement_rows
    raw = params[:movements]
    return [] if raw.blank?

    entries = if raw.is_a?(Array)
                raw
    else
                raw.keys.sort_by(&:to_i).map { |key| raw[key] }
    end
    entries.map { |row| row.respond_to?(:permit) ? row.permit(*ROW_FIELDS) : row }
  end

  def payment_params
    params.permit(payment: PERMITTED_PAYMENT_FIELDS)[:payment].to_h || {}
  end

  ROW_FIELDS = %i[description amount date type category_id category_name money_source_id
                  money_source_name source confidence selected duplicate].freeze
  PERMITTED_PAYMENT_FIELDS = %i[register amount date description category_id
                                principal_amount interest_amount insurance_amount other_amount
                                funding_money_source_id].freeze

  def rebuild_review
    document = Statements::Document.new(
      engine: :review,
      summary: Statements::Summary.from_h(parsed_summary_json),
      movements: rebuilt_movements
    )
    Statements::ReviewBuilder.call(user: current_user, document: document, money_source: @money_source)
  end

  def parsed_summary_json
    JSON.parse(params[:summary].to_s)
  rescue JSON::ParserError
    {}
  end

  # The posted rows only carry the review decisions; the payment block data is
  # not a movement, so payment-only submissions rebuild an empty document.
  def rebuilt_movements
    movement_rows.map(&:to_h)
  end

  def confirmation_notice(outcome)
    parts = [ I18n.t("statement_imports.confirmed", count: outcome[:expenses].length) ]
    payment = outcome[:payment]
    if payment
      parts << I18n.t("statement_imports.confirmed_with_payment",
                      amount: number_to_currency(payment.amount),
                      target: @money_source.name)
    else
      parts << I18n.t("statement_imports.confirmed_without_payment")
    end
    if outcome[:skipped_duplicates].to_i.positive?
      parts << I18n.t("statement_imports.skipped_duplicates", count: outcome[:skipped_duplicates])
    end
    if (parked = Array(outcome[:candidates])).any?
      parts << I18n.t("statement_imports.parked_candidates", count: parked.length)
    end
    parts.join(" ")
  end

  def not_found
    head :not_found
  end
end
