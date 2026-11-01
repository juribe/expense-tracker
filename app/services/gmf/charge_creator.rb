# frozen_string_literal: true

module Gmf
  # Gmf::ChargeCreator
  # Creates (or updates) the independent GMF expense linked to an original
  # movement. Idempotent by gmf_origin_type/id.
  #
  # Example:
  #   Gmf::ChargeCreator.call(user:, origin:, origin_type: "Expense",
  #                           amount:, date:, money_source:)
  class ChargeCreator
    def self.call(user:, origin:, origin_type:, amount:, date:, money_source:, estimated: true)
      new(user:, origin:, origin_type:, amount:, date:, money_source:, estimated:).call
    end

    def initialize(user:, origin:, origin_type:, amount:, date:, money_source:, estimated: true)
      @user = user
      @origin = origin
      @origin_type = origin_type
      @amount = amount.to_d
      @date = date.to_date
      @money_source = money_source
      @estimated = estimated
    end

    def call
      return nil if @amount <= 0

      category = gmf_category
      return nil unless category

      existing = Expense.where(
        user_id: @user.id, gmf_origin_type: @origin_type, gmf_origin_id: @origin.id
      ).first

      if existing
        existing.update!(
          amount: @amount, date: @date, money_source: @money_source,
          category: category, gmf_estimated: @estimated,
          gmf_status: @estimated ? "estimated" : "charged"
        )
        existing
      else
        Expense.create!(
          user: @user, category: category, amount: @amount, description: description,
          date: @date, source: "gmf", money_source: @money_source,
          gmf_origin_type: @origin_type, gmf_origin_id: @origin.id,
          gmf_estimated: @estimated,
          gmf_status: @estimated ? "estimated" : "charged"
        )
      end
    end

    private

    def gmf_category
      sub = Category.defaults.where(category_type: "expense", is_default: true)
                    .where("lower(name) = ?", "4x1.000 (gmf)").first
      return sub if sub

      parent = Category.defaults.where(category_type: "expense", is_default: true)
                       .where("lower(name) = ?", "impuestos y gravámenes").first
      unless parent
        parent = Category.create!(name: "Impuestos y gravámenes", category_type: "expense",
                                  is_default: true, user: nil)
      end

      Category.find_or_create_by!(name: "4x1.000 (GMF)", category_type: "expense",
                                  is_default: true, parent: parent, user: nil)
    end

    def description
      origin_label = case @origin
                     when Expense then "Gasto #{@origin.description.presence || @origin.id}"
                     when Transfer then "Transferencia"
                     else @origin.class.name
                     end
      "GMF 4x1.000 (#{origin_label})"
    end
  end
end
