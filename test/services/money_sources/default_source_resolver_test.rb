# frozen_string_literal: true

require "test_helper"

module MoneySources
  class DefaultSourceResolverTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Resolver User", email: "resolver_user@example.com", password: "password123")
    end

    test "simple mode always resolves General" do
      @user.update!(money_tracking_mode: "simple", money_tracking_mode_selected_at: Time.current)
      general = @user.general_money_source

      assert_equal general.id, DefaultSourceResolver.new(user: @user).resolve.id
      assert_equal general.id, DefaultSourceResolver.new(user: @user, explicit: @user.money_sources.create!(
        name: "Histórica", kind: "account"
      )).resolve.id
    end

    test "advanced mode respects an explicit source" do
      account = @user.money_sources.create!(name: "Cuenta", kind: "account")

      resolved = DefaultSourceResolver.new(user: @user, explicit: account).resolve

      assert_equal account.id, resolved.id
    end

    test "advanced mode resolves the configured default when no source is given" do
      account = @user.money_sources.create!(name: "Cuenta predeterminada", kind: "account")
      @user.update!(default_money_source: account)

      resolved = DefaultSourceResolver.new(user: @user).resolve

      assert_equal account.id, resolved.id
    end

    test "advanced mode returns nil without an explicit or default source" do
      assert_nil DefaultSourceResolver.new(user: @user).resolve
    end

    test "an explicit source owned by another user is never used" do
      other = User.create!(name: "Other Resolver", email: "other_resolver@example.com", password: "password123")
      foreign = other.money_sources.create!(name: "Ajena", kind: "account")
      default = @user.money_sources.create!(name: "Propia", kind: "account")
      @user.update!(default_money_source: default)

      assert_nil DefaultSourceResolver.new(user: @user, explicit: foreign).resolve
    end

    test "an inactive default source is ignored" do
      account = @user.money_sources.create!(name: "Inactiva", kind: "account", active: false)
      @user.update!(default_money_source: account)

      assert_nil DefaultSourceResolver.new(user: @user).resolve
    end
  end
end
