# frozen_string_literal: true

# CustomFinancialInstitutionsController
# "Otra entidad": user-owned institutions. Only the owner lists, edits or
# deletes their customs (all queries scope current_user); a custom entity is
# never automatically promoted to the global catalog. Deleting one that
# still backs money sources is blocked so no reference dangles.
class CustomFinancialInstitutionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_custom_institution, only: %i[edit update destroy]

  # Same convention as money_sources_controller: foreign records are a
  # plain 404 (no redirect, no leak).
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  def new
    @custom_institution = current_user.custom_financial_institutions.build
  end

  def create
    @custom_institution = current_user.custom_financial_institutions.build(custom_institution_params)
    if @custom_institution.save
      redirect_to financial_institutions_path, notice: t("custom_financial_institutions.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @custom_institution.update(custom_institution_params)
      redirect_to financial_institutions_path, notice: t("custom_financial_institutions.flashes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if MoneySource.where(user_id: current_user.id, institution: @custom_institution).exists?
      redirect_to financial_institutions_path,
                  alert: t("custom_financial_institutions.flashes.blocked_by_sources"),
                  status: :see_other
      return
    end

    @custom_institution.destroy
    redirect_to financial_institutions_path, notice: t("custom_financial_institutions.flashes.deleted")
  end

  private

  def set_custom_institution
    @custom_institution = current_user.custom_financial_institutions.find(params[:id])
  end

  def custom_institution_params
    params.require(:custom_financial_institution).permit(:name, :institution_type)
  end

  def not_found
    head :not_found
  end
end
