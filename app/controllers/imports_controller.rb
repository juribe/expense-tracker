# frozen_string_literal: true

class ImportsController < ApplicationController
  before_action :authenticate_user!

  def new
    @categories = Category.for_user(current_user)
  end

  def create
    if params[:file].blank?
      redirect_to new_import_path, alert: "Please select a CSV file."
      return
    end

    importer = RecurringTemplateImporter.new(user: current_user)
    importer.call(params[:file])

    if importer.errors.any?
      redirect_to new_import_path, alert: importer.errors.join(" ")
    else
      redirect_to monthly_expenses_path, notice: importer.notice
    end
  end
end
