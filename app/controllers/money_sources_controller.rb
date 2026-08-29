# frozen_string_literal: true

class MoneySourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_money_source, only: [ :show, :edit, :update, :destroy ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /money_sources
  def index
    @money_sources = current_user.money_sources.includes(:parent, :identifiers, :children).order(:kind, :name)
  end

  # GET /money_sources/1
  def show
  end

  # GET /money_sources/new
  def new
    @money_source = current_user.money_sources.build
  end

  # GET /money_sources/1/edit
  def edit
  end

  # POST /money_sources
  def create
    @money_source = current_user.money_sources.build(money_source_params)
    @identifier_rows = collect_identifier_rows

    @money_source.valid?
    collect_identifier_errors

    if @money_source.errors.empty? && @money_source.save
      persist_identifiers(@identifier_rows)
      redirect_to money_sources_path, notice: t("money_sources.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /money_sources/1
  def update
    @money_source.assign_attributes(money_source_params)
    @identifier_rows = collect_identifier_rows

    @money_source.valid?
    collect_identifier_errors

    if @money_source.errors.empty? && @money_source.save
      persist_identifiers(@identifier_rows)
      redirect_to money_sources_path, notice: t("money_sources.flashes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /money_sources/1
  def destroy
    @money_source.destroy
    redirect_to money_sources_path, notice: t("money_sources.flashes.deleted")
  end

  private

  def set_money_source
    @money_source = current_user.money_sources.find(params[:id])
  end

  def money_source_params
    params.require(:money_source).permit(:name, :kind, :bank, :parent_id, :starting_balance, :active)
  end

  def not_found
    head :not_found
  end

  def collect_identifier_rows
    return [] unless params[:identifiers].present?

    raw = params[:identifiers]
    raw = raw.values if raw.is_a?(ActionController::Parameters)

    Array(raw).filter_map do |ident|
      next if ident.blank?

      source = ident.respond_to?(:to_unsafe_h) ? ident.to_unsafe_h : ident
      permitted = ActionController::Parameters.new(source).permit(:id, :kind, :value)
      kind = permitted[:kind].to_s.strip
      value = permitted[:value].to_s.strip
      next if kind.blank? && value.blank?

      identifier = if permitted[:id].present?
                     @money_source.identifiers.find_by(id: permitted[:id]) || @money_source.identifiers.build
                   else
                     @money_source.identifiers.build
                   end

      identifier.kind = kind
      identifier.value = value
      identifier
    end
  end

  def collect_identifier_errors
    @identifier_rows.each do |identifier|
      next if identifier.valid?
      identifier.errors.full_messages.each do |msg|
        @money_source.errors.add(:base, t("money_sources.form.identifier_error_prefix", message: msg))
      end
    end
  end

  def persist_identifiers(identifier_rows)
    new_ids = []

    identifier_rows.each do |identifier|
      identifier.money_source = @money_source
      if identifier.save
        new_ids << identifier.id
      end
    end

    @money_source.identifiers.where.not(id: new_ids).destroy_all
  end
end
