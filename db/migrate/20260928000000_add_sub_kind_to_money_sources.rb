# frozen_string_literal: true

# Adds sub_kind to money_sources: the flavor within a kind, produced by the
# statement-import pipeline and the wizard's loan step. For loans it drives
# the funding/debt-payment capabilities (see MoneySource) — revolving loans
# disburse money, personal/vehicle/mortgage loans are debts only.
#
# Existing loans are backfilled from their names with the same regexes the
# view layer already used (ApplicationHelper#loan_identity), so no user has
# to recreate a loan and unmatched names stay nil (still a debt target).
class AddSubKindToMoneySources < ActiveRecord::Migration[8.0]
  PATTERNS = [
    [ /rotativo|revolving|sobregiro|credit.?card/i, "revolving" ],
    [ /hipotec|mortgage|hogar|vivienda|house/i, "mortgage" ],
    [ /veh[ií]culo|vehicular|auto\b|car\b|moto/i, "vehicle" ],
    [ /educaci[oó]n|estudio|student|universit/i, "education" ],
    [ /libre|personal|consumo/i, "personal" ],
    [ /empresa|negocio|pyme|comercial|business/i, "business" ]
  ].freeze

  def up
    add_column :money_sources, :sub_kind, :string

    change_table :money_sources do |t|
      t.index [ :kind, :sub_kind ]
    end

    MoneySource.where(kind: "loan").find_each do |loan|
      sub_kind = infer_sub_kind(loan.name, loan.bank)
      loan.update_columns(sub_kind: sub_kind) if sub_kind
    end
  end

  def down
    remove_index :money_sources, [ :kind, :sub_kind ]
    remove_column :money_sources, :sub_kind
  end

  private

  def infer_sub_kind(name, bank)
    haystack = [ name, bank ].compact.join(" ").downcase
    PATTERNS.each do |pattern, sub_kind|
      return sub_kind if haystack.match?(pattern)
    end
    nil
  end
end
