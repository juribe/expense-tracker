require "test_helper"

class EmailSourceTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "ES", email: "es_#{SecureRandom.hex(4)}@example.com", password: "password123")
    @other = User.create!(name: "OS", email: "os_#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "multiple sources per user" do
    @user.email_sources.create!(source_type: "forwarding", status: "active")
    @user.email_sources.create!(source_type: "forwarding", status: "pending_verification")
    assert_equal 2, @user.email_sources.count
  end

  test "user isolation" do
    source = @user.email_sources.create!(source_type: "forwarding", status: "active")
    assert_not_includes @other.email_sources, source
  end
end