# frozen_string_literal: true

# FinancialInstitutionsController
# "Mis entidades": the user's own custom institutions ("Otra entidad"). Each
# user renames or deletes ONLY their own rows (all queries scope
# current_user); deleting a custom entity that still backs money sources is
# blocked so no reference dangles. The shared global catalog is read-only by
# design and is surfaced inline (the money-source institution autocomplete
# lists catalog entities); users never edit global data here.
class FinancialInstitutionsController < ApplicationController
  before_action :authenticate_user!

  def index
    # Sorted purchases browse; the type grouping happens in the view over
    # FinancialInstitution::TYPES (stable taxonomy order).
    @custom_institutions = current_user.custom_financial_institutions.ordered
  end
end
