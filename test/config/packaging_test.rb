# frozen_string_literal: true

require "test_helper"

class PackagingTest < ActiveSupport::TestCase
  test "the docker build uses the committed npm lockfile" do
    dockerfile = Rails.root.join("Dockerfile").read

    assert_includes dockerfile, "package-lock.json"
    assert_includes dockerfile, "npm ci"
    refute_includes dockerfile, "yarn install"
    refute_includes dockerfile, "yarn.lock"
  end
end
