# frozen_string_literal: true

module MoneyTracking
  # Backfills the tracking mode and General source for accounts that existed
  # before the feature. Users with configured sources keep the advanced flow;
  # accounts without sources start simple. Already selected users and
  # registration-created accounts (which already own General) are skipped, so
  # the task is safe to re-run.
  #
  #   MoneyTracking::Backfill.call
  class Backfill
    def self.call(users: User.all)
      new(users: users).call
    end

    def initialize(users:)
      @users = users
    end

    def call
      counts = { detailed: 0, simple: 0, skipped: 0 }

      @users.where(money_tracking_mode_selected_at: nil).find_each do |user|
        if user.money_sources.exists?(general: true)
          counts[:skipped] += 1
          next
        end

        mode = user.money_sources.exists? ? "detailed" : "simple"
        user.money_tracking_mode = mode
        user.update_columns(money_tracking_mode: mode, money_tracking_mode_selected_at: Time.current)
        # Only the simple flow needs General. Advanced users keep their own
        # sources and should not receive an empty conversion account.
        MoneySources::General.ensure_for(user) if mode == "simple"
        counts[mode.to_sym] += 1
      end

      counts
    end
  end
end
