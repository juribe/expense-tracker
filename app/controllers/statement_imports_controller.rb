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
                                     filename: upload_filename, password: params[:password],
                                     money_source: @money_source,
                                     learner: Statements::LayoutLearner)

    return render_parse_failure(result) unless result.success?

    forget_registered_payment
    @review = Statements::ReviewBuilder.call(user: current_user, document: result.result,
                                             money_source: @money_source)

    respond_to do |format|
      format.html { render :review }
      format.json do
        render json: { ok: true, html: render_to_string(:review, formats: [ :html ], layout: false) }
      end
    end
  end

  # POST /money_sources/:money_source_id/statement_imports/confirm — creates
  # the selected movements. On success the review is re-rendered (so the user
  # can still register the payment) from the posted rows without navigating
  # away; on failure it is re-rendered with the errors, creating nothing.
  def confirm
    result = Statements::Confirmation.call(user: current_user, money_source: @money_source,
                                           movements: movement_rows)

    @review = rebuild_review
    @registered_payment = registered_payment
    if result.success?
      flash.now[:notice] = movement_notice(result.result)
      render :review
    else
      flash.now[:alert] = result.errors.to_sentence
      render :review, status: :unprocessable_entity
    end
  end

  # POST /money_sources/:money_source_id/statement_imports/pay — registers only
  # the payment for the debt. A progressive (fetch/JSON) request removes the
  # summary + payment form in place; a plain request leaves for the money source.
  def pay
    result = Statements::Confirmation.call(user: current_user, money_source: @money_source,
                                           movements: [], payment: payment_params)

    if result.success?
      remember_registered_payment(result.result[:payment])
      respond_to do |format|
        format.json { render json: { success: true, notice: payment_notice(result.result) } }
        format.html { redirect_to money_source_path(@money_source), notice: payment_notice(result.result) }
      end
    else
      @review = rebuild_review
      @registered_payment = registered_payment
      respond_to do |format|
        format.json { render json: { success: false, errors: result.errors }, status: :unprocessable_entity }
        format.html do
          flash.now[:alert] = result.errors.to_sentence
          render :review, status: :unprocessable_entity
        end
      end
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

  # Parse failure: the plain form redirects back to the upload with a flash
  # alert; an AJAX upload gets the errors as JSON so the page keeps the chosen
  # file and can show the message inline.
  def render_parse_failure(result)
    respond_to do |format|
      format.html do
        redirect_to new_money_source_statement_import_path(@money_source),
                    alert: t("statement_imports.parse_failed", error: result.errors.to_sentence)
      end
      format.json do
        render json: { ok: false, errors: result.errors }, status: :unprocessable_entity
      end
    end
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
  REGISTERED_PAYMENTS_SESSION_KEY = :statement_imports_registered_payments

  # The review survives several requests (confirm re-renders it), while the
  # payment form hides in the browser after an AJAX pay. Remembering the
  # registered payment per debt keeps it hidden when the review is re-rendered
  # server-side, even if the user changed its date or amount.
  def remember_registered_payment(payment)
    payments = session[REGISTERED_PAYMENTS_SESSION_KEY] || {}
    payments[@money_source.id.to_s] = {
      "amount" => payment.amount.to_s,
      "date" => payment.date.to_s
    }
    session[REGISTERED_PAYMENTS_SESSION_KEY] = payments
  end

  def forget_registered_payment
    payments = session[REGISTERED_PAYMENTS_SESSION_KEY]
    return if payments.blank?

    payments.delete(@money_source.id.to_s)
    session[REGISTERED_PAYMENTS_SESSION_KEY] = payments
  end

  def registered_payment
    data = session.dig(REGISTERED_PAYMENTS_SESSION_KEY, @money_source.id.to_s)
    return if data.blank?

    { amount: data["amount"].to_d, date: Date.parse(data["date"]) }
  rescue Date::Error
    nil
  end

  def rebuild_review
    document = Statements::Document.new(
      engine: review_engine,
      summary: Statements::Summary.from_h(parsed_summary_json),
      movements: rebuilt_movements
    )
    Statements::ReviewBuilder.call(user: current_user, document: document, money_source: @money_source)
  end

  # The review forms round-trip which engine parsed the statement (AI or a
  # learned direct parser) so the re-rendered review keeps showing the truth.
  def review_engine
    engine = params[:engine].to_s
    Statements::Document::ENGINES.include?(engine) ? engine.to_sym : :ai
  end

  def parsed_summary_json
    JSON.parse(params[:summary].to_s)
  rescue JSON::ParserError
    {}
  end

  # The posted rows only carry the review decisions; the payment block data is
  # not a movement, so payment-only submissions rebuild an empty document. The
  # parsed category name is re-fed as the AI transaction's "category" so the
  # rebuilt review keeps the row's category.
  def rebuilt_movements
    movement_rows.map do |row|
      movement = row.to_h
      movement["category"] ||= movement["category_name"]
      movement
    end
  end

  def movement_notice(outcome)
    parts = [ I18n.t("statement_imports.confirmed", count: outcome[:expenses].length) ]
    if outcome[:skipped_duplicates].to_i.positive?
      parts << I18n.t("statement_imports.skipped_duplicates", count: outcome[:skipped_duplicates])
    end
    parts.join(" ")
  end

  def payment_notice(outcome)
    I18n.t("statement_imports.confirmed_with_payment",
           amount: number_to_currency(outcome[:payment].amount),
           target: @money_source.name)
  end

  def not_found
    head :not_found
  end
end
