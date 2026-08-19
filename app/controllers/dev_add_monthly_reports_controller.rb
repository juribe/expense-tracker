# app/controllers/monthly_reports_controller.rb
class MonthlyReportsController < ApplicationController
  before_action :set_monthly_report, only: %i[show edit update destroy]

  # GET /monthly_reports
  # GET /monthly_reports.json
  def index
    @monthly_reports = MonthlyReport.order(report_date: :desc).page(params[:page])
    respond_to do |format|
      format.html
      format.json { render json: @monthly_reports }
    end
  end

  # GET /monthly_reports/1
  # GET /monthly_reports/1.json
  def show
    respond_to do |format|
      format.html
      format.json { render json: @monthly_report }
    end
  end

  # GET /monthly_reports/new
  def new
    @monthly_report = MonthlyReport.new
  end

  # GET /monthly_reports/1/edit
  def edit; end

  # POST /monthly_reports
  # POST /monthly_reports.json
  def create
    @monthly_report = MonthlyReport.new(monthly_report_params)

    respond_to do |format|
      if @monthly_report.save
        format.html { redirect_to @monthly_report, notice: 'Monthly report was successfully created.' }
        format.json { render :show, status: :created, location: @monthly_report }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @monthly_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /monthly_reports/1
  # PATCH/PUT /monthly_reports/1.json
  def update
    respond_to do |format|
      if @monthly_report.update(monthly_report_params)
        format.html { redirect_to @monthly_report, notice: 'Monthly report was successfully updated.' }
        format.json { render :show, status: :ok, location: @monthly_report }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @monthly_report.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /monthly_reports/1
  # DELETE /monthly_reports/1.json
  def destroy
    @monthly_report.destroy
    respond_to do |format|
      format.html { redirect_to monthly_reports_url, notice: 'Monthly report was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_monthly_report
    @monthly_report = MonthlyReport.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def monthly_report_params
    params.require(:monthly_report).permit(:title, :content, :report_date)
  end
end