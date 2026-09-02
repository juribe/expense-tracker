# frozen_string_literal: true

class MoneySourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_money_source, only: [ :show, :edit, :update, :destroy ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  FILTERS = {
    "cash" => %w[cash wallet account debit_card],
    "credit_cards" => %w[credit_card],
    "loans" => %w[loan]
  }.freeze

  # GET /money_sources
  def index
    scope = current_user.money_sources.includes(:parent, :tags, :children)

    @filter = params[:type].presence
    if @filter && FILTERS[@filter]
      scope = scope.where(kind: FILTERS[@filter])
    end

    @money_sources = scope.order(:kind, :name)
    @counts = FILTERS.each_with_object({}) do |(key, kinds), out|
      out[key] = current_user.money_sources.where(kind: kinds).count
    end
    @setup = current_user.financial_setups
                         .where(status: %w[in_progress dismissed])
                         .order(updated_at: :desc, id: :desc)
                         .first

    render @filter ? "index_#{@filter}" : :index
  end

  # GET /money_sources/1
  def show
  end

  # GET /money_sources/new
  def new
    @money_source = current_user.money_sources.build
    @money_source.build_credit_account
  end

  # GET /money_sources/1/edit
  def edit
  end

  # POST /money_sources
  def create
    @money_source = current_user.money_sources.build(money_source_params)
    @tag_values = collect_tag_values
    validate_with_tags

    if @money_source.errors.empty? && @money_source.save
      persist_tags(@tag_values)
      redirect_to kind_index_path(@money_source), notice: t("money_sources.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /money_sources/1
  def update
    @money_source.assign_attributes(money_source_params)
    @tag_values = collect_tag_values
    validate_with_tags

    if @money_source.errors.empty? && @money_source.save
      persist_tags(@tag_values)
      redirect_to kind_index_path(@money_source), notice: t("money_sources.flashes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /money_sources/1
  def destroy
    @money_source.destroy
    redirect_to kind_index_path(@money_source), notice: t("money_sources.flashes.deleted")
  end

  private

  def kind_index_path(source)
    case source.kind
    when "credit_card" then money_sources_credit_cards_path
    when "loan" then money_sources_loans_path
    else money_sources_cash_path
    end
  end

  def set_money_source
    @money_source = current_user.money_sources.find(params[:id])
  end

  def money_source_params
    permitted = [ :name, :kind, :bank, :parent_id, :starting_balance, :active, :identifier ]

    if params.dig(:money_source, :kind).to_s.in?(%w[credit_card loan]) || @money_source&.debt?
      permitted << {
        credit_account_attributes: [ :id, :credit_limit, :interest_rate, :interest_rate_type,
                                     :card_brand, :card_last_four, :statement_day, :payment_due_day,
                                     :principal_amount, :outstanding_balance, :installment_amount,
                                     :installment_count, :installments_paid, :payment_frequency, :start_date, :end_date ]
      }
    end

    normalize_money_params!(params.require(:money_source)).permit(permitted)
  end

  # The forms render Colombian-formatted values ("29,3", "1.234.567,89"); the
  # browser mask submits machine format ("29.3"). Normalize both so decimal
  # columns cast cleanly instead of failing "is not a number".
  def normalize_money_params!(money_source)
    money_source[:starting_balance] = MoneyFormat.normalize(money_source[:starting_balance]) if money_source[:starting_balance].present?

    credit_account = money_source[:credit_account_attributes]
    return money_source unless credit_account

    %w[credit_limit interest_rate principal_amount outstanding_balance installment_amount].each do |field|
      credit_account[field] = MoneyFormat.normalize(credit_account[field]) if credit_account[field].present?
    end
    money_source
  end

  def not_found
    head :not_found
  end

  # Tags are edited through plain `tags[...][value]` inputs (the old
  # identifiers pattern) and are persisted separately from strong params.
  def collect_tag_values
    raw = params.dig(:money_source, :tags)
    raw = params[:tags] if raw.blank?
    raw = raw.values if raw.is_a?(ActionController::Parameters)

    Array(raw).filter_map do |tag|
      value = tag.is_a?(ActionController::Parameters) ? tag[:value] : tag
      value.to_s.strip.downcase.presence
    end
  end

  def validate_with_tags
    @money_source.valid?

    @tag_values.each do |value|
      tag = @money_source.tags.find_or_initialize_by(value: value)
      next if tag.valid?

      tag.errors.full_messages.each do |message|
        @money_source.errors.add(:base, t("money_sources.form.tag_error_prefix", message: message))
      end
    end
  end

  def persist_tags(tag_values)
    new_ids = tag_values.filter_map do |value|
      tag = @money_source.tags.find_or_initialize_by(value: value)
      tag.save
      tag.id
    end

    @money_source.tags.where.not(id: new_ids).destroy_all
  end
end
