# HelpCenter::RatingsController
# POST /ayuda/valoracion
# Public article feedback. Visitors may rate anonymously; authenticated users
# are identified by their account. No raw IP addresses are persisted.
class HelpCenter::RatingsController < ApplicationController
  skip_before_action :authenticate_user!, only: :create
  skip_before_action :require_membership_selection, only: :create

  RATE_LIMIT = 10
  RATE_LIMIT_WINDOW = 1.hour

  rate_limit to: RATE_LIMIT, within: RATE_LIMIT_WINDOW, only: :create,
             store: RateLimitProxy.new, name: "help-center-rating",
             with: :respond_rate_limited

  def create
    @article = HelpArticleIndex.find_by!(maglev_page_id: params[:page_id], locale: HelpCenter::LOCALE)
    helpful = parse_helpful(params[:helpful])

    return respond_invalid if helpful.nil?

    HelpArticleRating.record!(
      maglev_page_id: @article.maglev_page_id,
      fingerprint: fingerprint,
      helpful: helpful
    )

    respond_success
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def parse_helpful(value)
    case value.to_s
    when "true", "1", "on" then true
    when "false", "0", "off" then false
    end
  end

  def fingerprint
    HelpCenter::RatingFingerprint.call(
      page: @article.maglev_page,
      user: current_user,
      request: request
    )
  end

  def respond_success
    respond_to do |format|
      format.json { render json: { ok: true, message: I18n.t("help_center.rating.thanks") } }
      format.html { redirect_to @article.url, status: :see_other, notice: I18n.t("help_center.rating.thanks") }
    end
  end

  def respond_invalid
    respond_to do |format|
      format.json do
        render json: { ok: false, error: I18n.t("help_center.rating.invalid") },
               status: :unprocessable_entity
      end
      format.html do
        redirect_to @article.url, status: :see_other, alert: I18n.t("help_center.rating.invalid")
      end
    end
  end

  def respond_rate_limited
    respond_to do |format|
      format.json do
        render json: { ok: false, error: I18n.t("help_center.rating.rate_limited") },
               status: :too_many_requests
      end
      format.html do
        redirect_to "/ayuda", status: :see_other,
                    alert: I18n.t("help_center.rating.rate_limited")
      end
    end
  end
end
