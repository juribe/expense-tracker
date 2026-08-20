# Override cssbundling-rails tasks to skip in test environment
# This prevents "No suitable tool found for installing JavaScript dependencies" errors

if Rails.env.test?
  Rake::Task["css:build"].clear if Rake::Task.task_defined?("css:build")
  Rake::Task["css:install"].clear if Rake::Task.task_defined?("css:install")
  
  namespace :css do
    task :build do
      # Skip CSS building in test environment
      puts "[css:build] Skipped in test environment"
    end
    
    task :install do
      # Skip CSS installation in test environment
      puts "[css:install] Skipped in test environment"
    end
  end
end
