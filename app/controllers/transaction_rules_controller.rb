# frozen_string_literal: true

# TransactionRulesController
# RESTful for TransactionRule, plus a member `patch :toggle_active`.
# Rules are always scoped to current_user.
class TransactionRulesController < ApplicationController
  CONDITION_FIELDS = {
    "merchant_contains" => "merchant_contains",
    "description_contains" => "description_contains",
    "money_source_condition" => "money_source_condition_id",
    "amount_gt" => "amount_gt",
    "amount_lt" => "amount_lt"
  }.freeze

  ACTION_FIELDS = {
    "category" => "category_id",
    "tag" => "tag",
    "money_source" => "action_money_source_id"
  }.freeze

  before_action :set_rule, only: [ :edit, :update, :destroy, :toggle_active ]
  before_action :set_form_data, only: [ :new, :create, :edit, :update ]

  def index
    @rules = current_user.transaction_rules.order(:created_at)
    @suggestions = TransactionRules::SuggestionService.new(current_user).suggestions
    @enabled_count = @rules.active.count
  end

  def new
    @rule = TransactionRule.new
    prefill_from_suggestion
  end

  def create
    @rule = current_user.transaction_rules.new(rule_params)

    if @rule.save
      redirect_to transaction_rules_path, notice: t("transaction_rules.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rule.update(rule_params)
      redirect_to transaction_rules_path, notice: t("transaction_rules.flashes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to transaction_rules_path, notice: t("transaction_rules.flashes.destroyed")
  end

  def toggle_active
    @rule.update!(enabled: !@rule.enabled?)
    redirect_to transaction_rules_path, notice: t("transaction_rules.flashes.#{@rule.enabled? ? 'enabled' : 'disabled'}")
  end

  def dismiss_suggestion
    current_user.dismiss_rule_suggestion!(params[:merchant])
    redirect_to transaction_rules_path, notice: t("transaction_rules.flashes.suggestion_dismissed")
  end

  private

  def set_rule
    @rule = current_user.transaction_rules.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t("transaction_rules.not_found")
    redirect_to transaction_rules_path
  end

  def set_form_data
    @categories = Category.for_user_and_type(current_user, "expense")
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  def rule_params
    permitted = params.expect(transaction_rule: [
      :name, :enabled, :priority,
      :merchant_contains, :description_contains,
      :money_source_condition_id, :amount_gt, :amount_lt,
      :category_id, :action_money_source_id, :tag
    ])
    keep_only_selected_fields(permitted, CONDITION_FIELDS, params[:condition_field])
    keep_only_selected_fields(permitted, ACTION_FIELDS, params[:action_field])
    normalize_blank_fields(permitted)
    permitted
  end

  # The form renders every condition/action input and hides the unselected
  # ones with CSS, so hidden inputs submit stale values. Drop any field that
  # is not the type picked in the condition/action selects.
  def keep_only_selected_fields(permitted, mapping, selected_key)
    selected = mapping[selected_key]
    return if selected.blank?

    (mapping.values - [ selected ]).each { |field| permitted[field] = nil }
  end

  def normalize_blank_fields(permitted)
    (CONDITION_FIELDS.values + ACTION_FIELDS.values).each do |field|
      permitted[field] = nil if permitted[field].is_a?(String) && permitted[field].blank?
    end
  end

  def prefill_from_suggestion
    kind = params[:suggestion]
    value = params[:value]
    category_id = params[:category_id]
    return if kind.blank? || value.blank?

    @rule.merchant_contains = value
    @rule.category_id = category_id if category_id.present?
  end
end
