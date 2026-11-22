# frozen_string_literal: true

module MoneySources
  # Applies a tracking-mode change and the General source conversion as one
  # transaction. The General record keeps its id and every movement, so the
  # history never needs to be recreated or reassigned.
  #
  #   MoneySources::ModeSwitch.new(user: user, mode: "detailed").call
  class ModeSwitch
    Result = Struct.new(:success, :mode, :errors, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(user:, mode:)
      @user = user
      @mode = mode.to_s
    end

    def call
      return failure([ "invalid money tracking mode" ]) unless @mode.in?(User::MONEY_TRACKING_MODES)

      ActiveRecord::Base.transaction do
        @user.lock!
        @mode == "detailed" ? switch_to_detailed : switch_to_simple
      end

      Result.new(success: true, mode: @user.money_tracking_mode, errors: [])
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      failure(errors_for(e))
    end

    private

    def switch_to_detailed
      general = General.ensure_for(@user)
      general.update!(kind: "account") unless general.kind == "account"

      @user.update!(
        money_tracking_mode: "detailed",
        money_tracking_mode_selected_at: Time.current,
        default_money_source_id: @user.default_money_source_id || general.id
      )
    end

    def switch_to_simple
      general = General.ensure_for(@user)
      general = reusable_general(general)

      @user.update!(
        money_tracking_mode: "simple",
        money_tracking_mode_selected_at: Time.current,
        default_money_source_id: nil
      )
      general
    end

    # A General account that acquired dependent structures stays intact; a new
    # basic General receives the simple flow so nothing is deleted or merged.
    def reusable_general(general)
      return general if general.kind == "general"

      if general.convertible_to_general?
        general.update!(kind: "general")
        general
      else
        general.update!(general: false)
        General.create_for(@user, kind: "general")
      end
    end

    def failure(errors)
      Result.new(success: false, mode: @user.money_tracking_mode, errors: Array(errors))
    end

    def errors_for(error)
      if error.respond_to?(:record) && error.record&.errors&.any?
        error.record.errors.full_messages
      else
        [ error.message ]
      end
    end
  end
end
