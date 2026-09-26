# frozen_string_literal: true

require "test_helper"

module Expenses
  # RowResolver: the deterministic resolver layer for tabular statement rows.
  # Structured rows keep their column values (with reference codes cleaned
  # from the description); free-text rows are re-derived through the
  # ExpenseResolver heuristic parser. Conflicts arrive flagged for review —
  # nothing is silently rewritten.
  class RowResolverTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Row Resolver User", email: "row-resolver@example.com", password: "password123")
      @categories = Category.for_user(@user).order(:name).to_a
    end

    def resolve(description:, amount: nil, date: nil)
      RowResolver.call(
        user: @user,
        description: description,
        amount: amount,
        date: date,
        categories: @categories,
        money_source_detector: MoneySources::Detector.new(user: @user)
      )
    end

    test "a structured row keeps column values and strips reference codes" do
      result = resolve(description: "PAGO A TRSF 1234567890 MERCADO", amount: 180_000, date: Date.new(2026, 9, 9))

      assert_equal "MERCADO", result.description
      assert_equal BigDecimal("180000"), result.amount
      assert_equal Date.new(2026, 9, 9), result.date
      assert_empty result.warnings
      refute result.revised
    end

    test "a free-text row without a column amount is re-derived through the heuristic parser" do
      result = resolve(description: "Mercado por 180.000 el viernes")

      friday = Date.current
      friday -= 1 until friday.wday == 5 && friday < Date.current
      assert result.revised
      assert_equal BigDecimal("180000"), result.amount
      assert_equal friday, result.date
      assert_includes result.description.downcase, "mercado"
    end

    test "a row whose description names a different amount than the column keeps the column and flags review" do
      result = resolve(description: "COMPRA POS NETFLIX 8900", amount: 77_000)

      assert_equal BigDecimal("77000"), result.amount
      assert result.warnings.any? { |warning| warning.include?("8900") && warning.include?("77000") }
    end

    test "a quantity group the column amount ignores is flagged from the row text" do
      result = resolve(description: "tres cafés de 8.500", amount: 8_500)

      assert_equal BigDecimal("8500"), result.amount
      assert result.warnings.any? { |warning| warning.include?("25500") }
    end

    test "a bank-only mention with several registered sources flags ambiguity" do
      cuenta = @user.money_sources.create!(name: "cuenta davibank", kind: "account", bank: "Davibank")
      cuenta.ensure_recognition.replace_identifiers(keyword: [ "cuenta davibank" ])
      tarjeta = @user.money_sources.create!(name: "tarjeta davibank", kind: "credit_card", bank: "Davibank")
      tarjeta.ensure_recognition.replace_identifiers(keyword: [ "tarjeta davibank", "tarjeta" ])

      result = resolve(description: "COMPRA POS DAVIBANK 45000", amount: 45_000)

      assert_equal "COMPRA POS DAVIBANK", result.description
      assert result.warnings.any? { |warning| warning.downcase.include?("ambiguous") }
    end

    test "an amount echoed in the description is dropped from the cleaned description" do
      result = resolve(description: "NETFLIX.COM 8900", amount: 8_900)

      assert_equal "NETFLIX.COM", result.description
      assert_empty result.warnings
    end
  end
end
