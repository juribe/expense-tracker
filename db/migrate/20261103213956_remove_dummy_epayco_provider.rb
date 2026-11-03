# frozen_string_literal: true

class RemoveDummyEpaycoProvider < ActiveRecord::Migration[8.1]
  def up
    # Remove the placeholder provider created during initial setup. It carried
    # test credentials ("test-p-key") and no settings, so it never worked and
    # could shadow the real "EPAYCO" provider because lookups are case
    # insensitive. Only delete rows that look like the placeholder.
    PaymentEngine::Provider.where(code: "epayco").find_each do |provider|
      creds = provider.credentials || {}
      settings = provider.settings || {}
      next unless creds["p_key"] == "test-p-key" || settings.blank?

      provider.destroy!
    end
  end

  def down
    # The placeholder is not restored on rollback.
  end
end
