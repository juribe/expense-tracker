class QaValidateDashboardReportsController < ApplicationController
  def index
    @reports = Report.all
    render json: @reports
  end

  def show
    @report = Report.find(params[:id])
    render json: @report
  end

  def create
    @report = Report.new(report_params)
    if @report.save
      render json: @report, status: :created
    else
      render json: @report.errors, status: :unprocessable_entity
    end
  end

  def update
    @report = Report.find(params[:id])
    if @report.update(report_params)
      render json: @report
    else
      render json: @report.errors, status: :unprocessable_entity
    end
  end

  def destroy
    @report = Report.find(params[:id])
    @report.destroy
    head :no_content
  end

  private

  def report_params
    params.require(:report).permit(:title, :content, :status)
  end
end