# Override cssbundling-rails tasks.
# This app ships plain stylesheets from app/assets/stylesheets and has no
# `build:css` npm script, so the bundler tasks are no-ops. Applied in every
# environment so `db:test:prepare` / asset tasks never fail with
# "Missing script: build:css".

Rake::Task["css:build"].clear if Rake::Task.task_defined?("css:build")
Rake::Task["css:install"].clear if Rake::Task.task_defined?("css:install")

namespace :css do
  task :build do
    # No-op: CSS is served directly from app/assets/stylesheets.
  end

  task :install do
    # No-op: no CSS build dependencies are used by this app.
  end
end
