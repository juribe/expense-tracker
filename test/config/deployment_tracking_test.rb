# frozen_string_literal: true

require "test_helper"

class DeploymentTrackingTest < ActiveSupport::TestCase
  setup do
    @deploy_config = Rails.root.join("config/deploy.yml").read
    @workflow = Rails.root.join(".github/workflows/deploy.yml").read
    @secrets_example = Rails.root.join(".kamal/secrets.example").read
  end

  test "Kamal receives the deployed Git SHA as APP_VERSION" do
    assert_includes @deploy_config, "APP_VERSION: <%= app_version %>"
    assert_includes @deploy_config, 'ENV["APP_VERSION"]'
    assert_includes @deploy_config, "git rev-parse HEAD"
  end

  test "Kamal passes the Rollbar project token to the application" do
    secret_section = @deploy_config[/secret:\n(?:.*\n)*/]

    assert_includes secret_section, "- ROLLBAR_ACCESS_TOKEN"
  end

  test "the deploy workflow uses the commit that was tested" do
    assert_includes @workflow,
                    "APP_VERSION: ${{ github.event.workflow_run.head_sha || github.sha }}"
  end

  test "the deploy workflow reads the Rollbar token from GitHub secrets" do
    assert_includes @workflow, "ROLLBAR_ACCESS_TOKEN: ${{ secrets.ROLLBAR_ACCESS_TOKEN }}"
    assert_includes @workflow,
                    "ROLLBAR_DEPLOY_TOKEN: ${{ secrets.ROLLBAR_SERVER_ACCESS_TOKEN || secrets.ROLLBAR_ACCESS_TOKEN }}"
    refute_match(/[0-9a-f]{64}/, @workflow)
  end

  test "deployment notifications run only after a successful deploy" do
    notification = @workflow[/- name: Report deployment to Rollbar\n(?:.*\n)*?(?=\n      - name:|\z)/]

    refute_nil notification
    assert_includes notification, "if: ${{ success()"
    assert_includes notification, "!inputs.dump_logs"
    assert_includes notification, "!inputs.setup_cms"
    assert_operator @workflow.index("Report deployment to Rollbar"), :>, @workflow.index("- name: Deploy with Kamal")
  end

  test "deployment notifications call the Rollbar deploy API with the tested revision" do
    assert_includes @workflow, "https://api.rollbar.com/api/1/deploy/"
    assert_includes @workflow, '"revision"'
    assert_includes @workflow, '"environment"'
    assert_includes @workflow, '"status": "succeeded"'
  end

  test "the manual secrets template documents the Rollbar token" do
    assert_includes @secrets_example, "ROLLBAR_ACCESS_TOKEN=$ROLLBAR_ACCESS_TOKEN"
  end

  test "documentation covers production secrets and verification" do
    readme = Rails.root.join("README.md").read
    guide = Rails.root.join("docs/error_monitoring.md").read

    assert_includes readme, "docs/error_monitoring.md"
    assert_includes guide, "ROLLBAR_ACCESS_TOKEN"
    assert_includes guide, "APP_VERSION"
    assert_includes guide, "kamal app exec"
  end
end
