# frozen_string_literal: true

class MoneySourcesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_money_source, only: [ :show, :edit, :update, :destroy ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /money_sources
  def index
    @money_sources = current_user.money_sources.includes(:parent, :tags, :children).order(:kind, :name)
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
    @tag_values = collect_tag_values
    validate_with_tags

    if @money_source.errors.empty? && @money_source.save
      persist_tags(@tag_values)
      redirect_to money_sources_path, notice: t("money_sources.flashes.created")
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
