# frozen_string_literal: true

class ImportsController < ApplicationController
  DRAFT_CACHE_TTL = 30.minutes
  DRAFT_SESSION_KEY = :imports_draft_token

  before_action :authenticate_user!

  def new
    @categories = Category.for_user(current_user)
  end

  # Parse + validate the uploaded CSV, keep the draft in the cache behind a
  # token in the session (the draft can exceed the 4 KB cookie limit) and go
  # to the preview screen.
  def upload
    if params[:file].blank?
      redirect_to new_import_path, alert: t("imports.file_required")
      return
    end

    importer = RecurringTemplateImporter.new(user: current_user)
    rows = importer.preview(params[:file])

    if importer.errors.any?
      redirect_to new_import_path, alert: importer.errors.join(" ")
      return
    end

    draft = {
      "rows" => rows,
      "default_category_id" => params[:default_category_id].presence
    }
    token = new_draft_token
    Rails.cache.write(token, draft, expires_in: DRAFT_CACHE_TTL)
    session[DRAFT_SESSION_KEY] = token

    redirect_to import_preview_path
  end

  def preview
    @draft = load_draft

    if @draft.nil?
      redirect_to new_import_path, alert: t("imports.file_required")
      return
    end

    @rows = @draft["rows"]
    @category_options = category_options
  end

  # Confirm the preview: resolve each row (user selection first, then the
  # category resolved at upload, then the default category) and import what
  # validates. Skipped rows are reported back.
  def create
    draft = load_draft
    if draft.nil?
      redirect_to new_import_path, alert: t("imports.file_required")
      return
    end

    session.delete(DRAFT_SESSION_KEY)

    importer = RecurringTemplateImporter.new(user: current_user)
    importer.import(draft["rows"],
                    category_ids: imported_category_ids,
                    default_category_id: draft["default_category_id"])

    if importer.errors.any?
      redirect_to new_import_path, alert: importer.errors.join(" ")
    elsif importer.templates.empty?
      redirect_to new_import_path, alert: importer.row_errors.join(" ")
    elsif importer.row_errors.any?
      redirect_to monthly_expenses_path, notice: importer.notice, alert: importer.row_errors.join(" ")
    else
      redirect_to monthly_expenses_path, notice: importer.notice
    end
  end

  private

  def new_draft_token
    "imports_draft/#{current_user.id}/#{SecureRandom.hex(12)}"
  end

  def load_draft
    token = session[DRAFT_SESSION_KEY]
    return nil if token.blank?

    @load_draft ||= Rails.cache.read(token)
  end

  # Dropdown choices per row kind: [name, id] pairs for the user's categories.
  def category_options
    @category_options ||= Category.for_user(current_user)
                                  .where(category_type: %w[expense income])
                                  .order(:name)
                                  .group_by(&:category_type)
                                  .transform_values { |list| list.map { |category| [category.name, category.id] } }
  end

  def imported_category_ids
    params[:category_ids].respond_to?(:to_unsafe_h) ? params[:category_ids].to_unsafe_h : {}
  end
end
