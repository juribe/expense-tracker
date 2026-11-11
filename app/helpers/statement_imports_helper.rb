# frozen_string_literal: true

# StatementImportsHelper
# Methods: statement_import_locked?
#
# Example: statement_import_locked? # => true for free users
module StatementImportsHelper
  # Free users keep the payment action visible but locked; it opens the
  # Premium upsell modal instead of the statement importer.
  def statement_import_locked?
    !user_access.access_premium?
  end
end
