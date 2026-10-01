# frozen_string_literal: true

require "test_helper"

module ApplicationCable
  class ConnectionTest < ActionCable::Connection::TestCase
    WardenStub = Struct.new(:user)

    test "rejects connection without a signed-in user" do
      assert_reject_connection { connect(env: { "warden" => WardenStub.new(nil) }) }
    end

    test "connects with the signed-in user as current_user" do
      user = User.create!(
        name: "Cable User",
        email: "cable_user@example.com",
        password: "password123"
      )
      connect(env: { "warden" => WardenStub.new(user) })
      assert_equal user.id, connection.current_user.id
    end
  end
end
