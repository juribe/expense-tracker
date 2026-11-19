# frozen_string_literal: true

# Admin::UsersController
# GET /admin/users lists registered users; DELETE /admin/users/:id removes
# one account. Admin-only.
class Admin::UsersController < ApplicationController
  before_action :require_admin!

  def index
    @users = User
             .left_joins(:money_sources)
             .select("users.*, COUNT(money_sources.id) AS money_sources_count")
             .group("users.id")
             .order(users: { created_at: :desc })
             .paginate(page: params[:page], per_page: PER_PAGE)
  end

  def destroy
    user = User.with_deletion_dependencies.find(params[:id])

    if user == current_user
      redirect_to admin_users_path, alert: t("admin.users.cannot_delete_self")
      return
    end

    if user.destroy
      redirect_to admin_users_path, notice: t("admin.users.deleted")
    else
      redirect_to admin_users_path, alert: t("admin.users.delete_failed")
    end
  end

  def bulk_destroy
    selected_ids = Array(params[:user_ids]).compact_blank
    ids = selected_ids - [ current_user.id.to_s ]

    if ids.empty?
      message = selected_ids.any? ? t("admin.users.cannot_delete_self") : t("admin.users.bulk.none_selected")
      redirect_to admin_users_path, alert: message
      return
    end

    deleted_count, failed_count = destroy_users(ids)

    if deleted_count.zero?
      redirect_to admin_users_path, alert: t("admin.users.bulk.delete_failed")
    elsif failed_count.positive?
      redirect_to admin_users_path,
                  alert: t("admin.users.bulk.partially_deleted", deleted: deleted_count, failed: failed_count)
    else
      redirect_to admin_users_path, notice: t("admin.users.bulk.deleted", count: deleted_count)
    end
  end

  private

  def destroy_users(ids)
    deleted_count = 0
    failed_count = 0

    User.with_deletion_dependencies.where(id: ids).each do |user|
      user.destroy ? deleted_count += 1 : failed_count += 1
    end

    [ deleted_count, failed_count ]
  end
end
