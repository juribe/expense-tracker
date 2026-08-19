class BuildDashboardController < ApplicationController
  def index
    @dashboards = Dashboard.all
  end

  def show
    @dashboard = Dashboard.find(params[:id])
  end

  def new
    @dashboard = Dashboard.new
  end

  def create
    @dashboard = Dashboard.new(dashboard_params)
    if @dashboard.save
      redirect_to @dashboard, notice: 'Dashboard was successfully created.'
    else
      render :new
    end
  end

  def edit
    @dashboard = Dashboard.find(params[:id])
  end

  def update
    @dashboard = Dashboard.find(params[:id])
    if @dashboard.update(dashboard_params)
      redirect_to @dashboard, notice: 'Dashboard was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @dashboard = Dashboard.find(params[:id])
    @dashboard.destroy
    redirect_to dashboards_path, notice: 'Dashboard was successfully destroyed.'
  end

  private

  def dashboard_params
    params.require(:dashboard).permit(:title, :description)
  end
end