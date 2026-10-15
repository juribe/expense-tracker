# frozen_string_literal: true

module Transfers
  # QuickActions
  # The movement concept table: every entry moves money with a single Transfer,
  # but the action's name and allowed destinations depend on the origin kind.
  #   cash                  → deposit into an account, send to pocket
  #   account/debit/wallet  → withdraw cash, transfer, send to pocket
  #   credit card           → advance (accounts + cash)
  #   revolving loan        → disbursement into accounts
  #   pocket                → release back into accounts + cash
  # Amortizing loans never send money, and inactive sources offer nothing.
  # TransfersController#quick_new re-validates every origin/mode pair, so the
  # UI menu and the form guard must stay in sync with this table.
  module QuickActions
    class << self
      def for(source, cash_available: false)
        return [] if source.nil? || !source.active?

        if source.cash?
          [ deposit_action, pocket_action ]
        elsif source.credit_card?
          [ advance_action ]
        elsif source.pocket?
          [ release_action ]
        elsif source.revolving?
          [ disburse_action ]
        elsif source.payment_source?
          build_payment_source_actions(source, cash_available)
        else
          []
        end
      end

      private

      def build_payment_source_actions(source, cash_available)
        actions = []
        actions << withdraw_action if cash_available && !source.debt?
        actions << transfer_action
        actions << pocket_action unless source.debt?
        actions
      end

      def deposit_action
        { mode: "transfer", icon: "building-bank", title: I18n.t("transfers.quick.deposit") }
      end

      def withdraw_action
        { mode: "withdraw", icon: "cash", title: I18n.t("transfers.quick.withdraw") }
      end

      def transfer_action
        { mode: "transfer", icon: "arrows-left-right", title: I18n.t("transfers.quick.transfer") }
      end

      def pocket_action
        { mode: "pocket", icon: "pig-money", title: I18n.t("transfers.quick.pocket") }
      end

      def advance_action
        { mode: "advance", icon: "cash", title: I18n.t("transfers.quick.advance") }
      end

      def disburse_action
        { mode: "disburse", icon: "coin", title: I18n.t("transfers.quick.disburse") }
      end

      def release_action
        { mode: "release", icon: "building-bank", title: I18n.t("transfers.quick.release") }
      end
    end
  end
end
