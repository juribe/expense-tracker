# frozen_string_literal: true

# Daily database backup task.
#   bin/rails db:backup          -> runs script/db_backup.sh
#   bin/rails db:backup[30]      -> retain 30 days
namespace :db do
  desc "Back up the development database (pg_dump custom format)"
  task :backup, [ :retention_days ] => :environment do |_, args|
    retention = args[:retention_days] || 14
    script = Rails.root.join("script", "db_backup.sh")
    abort "Backup script not found: #{script}" unless script.exist?

    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    system({ "DATABASE_NAME" => ActiveRecord::Base.connection_db_config.database,
             "DATABASE_HOST" => (cfg[:host] || "127.0.0.1").to_s,
             "DATABASE_PORT" => (cfg[:port] || 5432).to_s,
             "DATABASE_USERNAME" => (cfg[:username] || ENV.fetch("USER", "postgres")).to_s,
             "DATABASE_PASSWORD" => (cfg[:password] || "").to_s },
           script.to_s, retention.to_s) || abort("Backup failed")
  end
end
