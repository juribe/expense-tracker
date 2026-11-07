# HelpCenter::RatingFingerprint
# Builds an opaque visitor fingerprint without storing raw IP addresses.
#
# Example: HelpCenter::RatingFingerprint.call(page: page, user: current_user, request: request)
class HelpCenter::RatingFingerprint
  def self.call(page:, user:, request:)
    new(page: page, user: user, request: request).call
  end

  def initialize(page:, user:, request:)
    @page = page
    @user = user
    @request = request
  end

  def call
    return "user:#{@user.id}" if @user

    "anon:#{Digest::SHA256.hexdigest(anonymous_payload)}"
  end

  private

  def anonymous_payload
    [
      Rails.application.secret_key_base,
      @request.remote_ip.to_s,
      @request.user_agent.to_s,
      @page.id,
      Date.current.iso8601
    ].join(":")
  end
end
