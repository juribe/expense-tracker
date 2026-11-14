# frozen_string_literal: true

require "test_helper"

# Guards the temporary deploy steps that create the public data deletion page
# and add its footer link while the content is not yet edited from Maglev.
class DeployWorkflowTest < ActiveSupport::TestCase
  test "el deploy publica la página de eliminación de datos y su enlace" do
    commands = deploy_steps.filter_map { |step| step["run"] }.join("\n")

    assert_includes commands, "bin/rails yogasto:setup_data_deletion"
    assert_includes commands, "bin/rails yogasto:link_data_deletion_in_footer"
  end

  private

  def deploy_steps
    YAML.safe_load_file(Rails.root.join(".github/workflows/deploy.yml"))["jobs"]["deploy"]["steps"]
  end
end
