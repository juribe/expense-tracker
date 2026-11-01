# frozen_string_literal: true

# GmfUvtYearsController
# Admin-only CRUD for annual UVT values used by GMF calculations.
class GmfUvtYearsController < ApplicationController
  before_action :require_admin!

  def index
    @uvt_years = GmfUvtYear.order(year: :desc)
  end

  def create
    @uvt_year = GmfUvtYear.new(uvt_year_params)
    if @uvt_year.save
      redirect_to gmf_uvt_years_path, notice: "UVT guardado"
    else
      @uvt_years = GmfUvtYear.order(year: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    @uvt_year = GmfUvtYear.find(params[:id])
    if @uvt_year.update(uvt_year_params)
      redirect_to gmf_uvt_years_path, notice: "UVT actualizado"
    else
      @uvt_years = GmfUvtYear.order(year: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    GmfUvtYear.find(params[:id]).destroy
    redirect_to gmf_uvt_years_path, notice: "UVT eliminado"
  end

  private

  def uvt_year_params
    params.expect(gmf_uvt_year: [:year, :value])
  end
end
