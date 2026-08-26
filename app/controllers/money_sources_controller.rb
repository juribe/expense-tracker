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
    if @money_source.save
      save_identifiers(@money_source)
      redirect_to money_sources_path, notice: "Money source was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /money_sources/1
  def update
    if @money_source.update(money_source_params)
      save_identifiers(@money_source)
      redirect_to money_sources_path, notice: "Money source was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /money_sources/1
  def destroy
    @money_source.destroy
    redirect_to money_sources_path, notice: "Money source was successfully deleted."
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

  def save_identifiers(money_source)
    return unless params[:identifiers].present?

    raw = params[:identifiers]
    raw = raw.values if raw.is_a?(ActionController::Parameters)

    new_ids = []

    Array(raw).each do |ident|
      next if ident.blank?

      source = ident.respond_to?(:to_unsafe_h) ? ident.to_unsafe_h : ident
      permitted = ActionController::Parameters.new(source).permit(:kind, :value)
      kind = permitted[:kind].to_s.strip
      value = permitted[:value].to_s.strip
      next if kind.blank? || value.blank?

      identifier = money_source.identifiers.find_or_initialize_by(kind: kind)
      identifier.value = value
      identifier.save!
      new_ids << identifier.id
    end

    money_source.identifiers.where.not(id: new_ids).destroy_all
  end
end
