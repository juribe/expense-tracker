# frozen_string_literal: true

require "test_helper"
require "open3"

# Exercises script/db_backup.sh with a stub pg_dump: permissions, encryption
# and the refusal to run without a key.
class DbBackupScriptTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("script/db_backup.sh")

  setup do
    @dir = Dir.mktmpdir
    @bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(@bin)
    fake = File.join(@bin, "pg_dump")
    File.write(fake, <<~SH)
      #!/bin/sh
      for arg in "$@"; do
        case "$arg" in --file=*) out="${arg#--file=}" ;; esac
      done
      printf 'dump-content' > "$out"
    SH
    File.chmod(0o755, fake)

    @backup_dir = File.join(@dir, "backups")
    @key = File.join(@dir, "backup.key")
    File.write(@key, "test-passphrase")
    File.chmod(0o600, @key)
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  test "creates a private encrypted backup and removes the plaintext dump" do
    status, error = run_script

    assert status.success?, error
    encrypted = Dir.glob(File.join(@backup_dir, "*.dump.enc"))
    assert_equal 1, encrypted.size
    assert_equal 0o700, File.stat(@backup_dir).mode & 0o777
    assert_equal 0o600, File.stat(encrypted.first).mode & 0o777
    assert_empty Dir.glob(File.join(@backup_dir, "*.dump"))
    assert_empty Dir.glob(File.join(@backup_dir, ".*.tmp"))

    decrypted, = Open3.capture2(
      "openssl", "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "200000",
      "-in", encrypted.first, "-pass", "file:#{@key}"
    )
    assert_equal "dump-content", decrypted
  end

  test "refuses to run without an encryption key" do
    status, error = run_script("BACKUP_ENCRYPTION_KEY_FILE" => File.join(@dir, "missing.key"))

    refute status.success?
    assert_match(/key/i, error)
    assert_empty Dir.glob(File.join(@backup_dir, "*.dump*"))
  end

  test "refuses a key readable by other users" do
    File.chmod(0o644, @key)

    status, error = run_script

    refute status.success?
    assert_match(/600 or 400|permission/i, error)
    assert_empty Dir.glob(File.join(@backup_dir, "*.dump*"))
  end

  test "can create a private unencrypted dump when explicitly requested" do
    status, error = run_script("BACKUP_ENCRYPTION" => "none")

    assert status.success?, error
    dump = Dir.glob(File.join(@backup_dir, "*.dump"))
    assert_equal 1, dump.size
    assert_equal 0o600, File.stat(dump.first).mode & 0o777
  end

  private

  def run_script(env = {})
    values = {
      "PATH" => "#{@bin}:#{ENV['PATH']}",
      "BACKUP_DIR" => @backup_dir,
      "DATABASE_NAME" => "expense_tracker_test",
      "BACKUP_ENCRYPTION_KEY_FILE" => @key
    }.merge(env)

    _output, error, status = Open3.capture3(values, "bash", SCRIPT.to_s, "14")
    [ status, error ]
  end
end
