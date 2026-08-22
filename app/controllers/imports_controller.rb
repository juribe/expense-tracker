# frozen_string_literal: true

class ImportsController < ApplicationController
  before_action :authenticate_user!

  def new
    @categories = Category.all
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
      redirect_to recurring_templates_path(kind: "expense"), notice: importer.notice
    end
  end
end