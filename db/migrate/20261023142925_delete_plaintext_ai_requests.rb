class DeletePlaintextAiRequests < ActiveRecord::Migration[8.1]
  # AiRequest rows are telemetry/debug history. Once encryption at rest is
  # enabled for prompt/output, the legacy plaintext rows cannot be read back
  # (the decryptor returns nil on non-ciphertext input), so they are wiped
  # instead of lingering as clear financial conversation content.
  def up
    AiRequest.delete_all
  end

  def down
  end
end
