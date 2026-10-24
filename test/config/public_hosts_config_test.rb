# frozen_string_literal: true

require "test_helper"

# The public host list is parsed once into config.x.public_hosts so host
# protection, Action Cable origins and future consumers share one source.
class PublicHostsConfigTest < ActiveSupport::TestCase
  test "defaults to expensetracker.com when RAILS_PUBLIC_HOSTS is unset" do
    public_hosts = Rails.application.config.x.public_hosts

    assert_equal [ "expensetracker.com" ], public_hosts
  end

  test "is exposed as an array so consumers can map origins" do
    public_hosts = Rails.application.config.x.public_hosts

    assert_kind_of Array, public_hosts
    public_hosts.each { |host| assert_not_nil host.strip }
  end
end
