# frozen_string_literal: true

# ProfilesController
# Shows the account profile and updates marketing communication preferences.
class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    @marketing_consent = UserConsent.marketing_status(current_user)
  end

  def update_communications
    granted = marketing_consent_params[:marketing_consent].to_s == "1"
    current_consent = UserConsent.marketing_status(current_user)

    if current_consent && current_consent.granted? == granted
      redirect_to profile_path, notice: I18n.t("profile.communications.unchanged")
      return
    end

    UserConsent.record_marketing_consent!(current_user, granted: granted)
    notice_key = granted ? "profile.communications.granted_notice" : "profile.communications.withdrawn_notice"
    redirect_to profile_path, notice: I18n.t(notice_key)
  end

  private

  def marketing_consent_params
    params.expect(user: [ :marketing_consent ])
  end
end
