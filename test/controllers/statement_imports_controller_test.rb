# frozen_string_literal: true

require "test_helper"

# StatementImportsController: file-based statement import into the
# apply-payment flow of a credit card / loan money source.
class StatementImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Import User", email: "statement_imports@example.com", password: "password123")
    sign_in @user
    @card = @user.money_sources.create!(name: "Visa", kind: "credit_card", starting_balance: 0)
    @account = @user.money_sources.create!(name: "Ahorros", kind: "account", starting_balance: 100_000)
    @category = Category.create!(name: "Restaurantes", user: @user, category_type: "expense")
    @document = Statements::Document.new(
      engine: :ai,
      summary: Statements::Summary.new(total_due: "1250300", min_payment: "62515",
                                       interest_charged: "45200", due_date: "2026-09-04"),
      source: ParsedStatement.new(kind: "credit_card", name: "Visa", bank: "Davivienda", card_last_four: "8976"),
      movements: [
        { date: "2026-08-23", description: "Restaurante XYZ", amount: 48_500, type: "expense" },
        { date: "2026-08-24", description: "Pago recibido", amount: 500_000, type: "income" }
      ]
    )
  end

  # ------------------------------------------------------------------- new
  test "GET new renders the upload form for a debt source" do
    get new_money_source_statement_import_path(@card)

    assert_response :success
    assert_select "form[action*='statement_imports']"
    assert_select "input[type='file']"
    assert_select "input[type='password']"
  end

  test "GET new redirects a non-debt source back to its page" do
    get new_money_source_statement_import_path(@account)

    assert_redirected_to money_source_path(@account)
  end

  # ---------------------------------------------------------------- create
  test "POST create renders the review with the summary and movements" do
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }

      assert_response :success
      assert_select "h5", text: /Resumen del extracto/
      assert_select "td", text: /Restaurante XYZ/
      assert_select "td", text: /Pago recibido/
      # The payment JS binds at form scope: totals, components and the amount
      # field must all live inside the bound form (payments.js requirements).
      assert_select "form[data-payment-distribution-form='true']", 1 do
        assert_select "[data-payment-expense-total]"
        assert_select "[data-payment-total-display]"
        assert_select "[data-payment-amount]"
        assert_select "input[data-payment-component='true']", 4
        assert_select "select#payment_funding_money_source_id[required]"
      end
    end
  end

  test "POST create highlights repeated movements as possible double charges" do
    document = Statements::Document.new(
      engine: :ai,
      summary: @document.summary,
      source: @document.source,
      movements: [
        { date: "2026-08-23", description: "Doble cobro", amount: 12_000, type: "expense" },
        { date: "2026-08-23", description: "Doble cobro", amount: 12_000, type: "expense" }
      ]
    )

    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }

      assert_response :success
      assert_select "tr.table-danger", 2
      assert_select "span.badge.bg-danger", text: "Posible doble cobro", count: 2
    end
  end

  test "POST create sends the parsed movements back for review" do
    document = @document
    review_params = {}
    spy = lambda do |user:, file_data:, filename:, password:, money_source: nil, learner: nil|
      review_params.merge!(file_data: file_data, filename: filename, password: password,
                           money_source: money_source, learner: learner)
      ServiceResult.success(document)
    end

    stub_method(Statements::Parser, :call, spy) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf",
                                                                 password: "1234" }
      assert_response :success
    end

    assert_equal "data:application/octet-stream;base64,cGRmLWJ5dGVz", review_params[:file_data]
    assert_equal "extracto.pdf", review_params[:filename]
    assert_equal "1234", review_params[:password]
    assert_equal @card, review_params[:money_source]
    assert_equal Statements::LayoutLearner, review_params[:learner]
  end

  test "POST create redirects back to the upload when parsing fails" do
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.error([ "bad document" ]) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }

      assert_redirected_to new_money_source_statement_import_path(@card)
      assert_match /bad document/, flash[:alert].to_s
    end
  end

  # ---------------------------------------------- AJAX upload (JSON format)
  test "POST create responds with the review HTML for an AJAX upload" do
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), as: :json,
           params: { file: "pdf-bytes", filename: "extracto.pdf" }

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal true, body["ok"]
      assert body["html"].include?("Resumen del extracto")
      assert body["html"].include?("Restaurante XYZ")
      assert body["html"].include?("Pago recibido")
      # The AJAX payload is the review fragment, not a full page: it is injected
      # in place, so it must not carry the layout.
      assert_not_includes body["html"], "<!DOCTYPE html>"
      assert body["html"].lstrip.start_with?("<div")
    end
  end

  test "POST create responds with JSON errors when an AJAX upload fails to parse" do
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.error([ "bad document" ]) }) do
      post money_source_statement_imports_path(@card), as: :json,
           params: { file: "pdf-bytes", filename: "extracto.pdf" }

      assert_response :unprocessable_entity
      body = JSON.parse(response.body)
      assert_equal false, body["ok"]
      assert_includes body["errors"], "bad document"
    end
  end

  # --------------------------------------------------------------- confirm
  test "POST confirm creates the selected movements and stays on the review" do
    assert_difference -> { Expense.count }, 1 do
      assert_no_difference -> { Payment.count } do
        post confirm_money_source_statement_imports_path(@card), params: {
          summary: @document.summary.to_h.to_json,
          movements: [
            { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01", category_id: @category.id, selected: "1" },
            { description: "Supermercado", amount: "210000", date: "2026-09-02", category_id: @category.id, selected: "0" }
          ]
        }
      end
    end

    assert_response :success
    assert_equal 1, Expense.where(source: "statement_file", description: "Restaurante XYZ").count
  end

  test "POST confirm parses the real form shape when movements arrive as an indexed hash" do
    assert_difference -> { Expense.count }, 1 do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: {
          "0" => { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01",
                   category_id: @category.id, selected: "1" },
          "1" => { description: "Supermercado", amount: "210000", date: "2026-09-02",
                   category_id: @category.id }
        }
      }
    end

    assert_response :success
    assert_equal 1, Expense.where(source: "statement_file", description: "Restaurante XYZ").count
  end

  test "POST confirm re-renders with an error when a selected movement has no category" do
    assert_no_difference -> { Expense.count } do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: [ { description: "MAXIDIFICACION RARA", amount: "48500", date: "2026-09-01",
                       money_source_id: @card.id, selected: "1" } ]
      }
    end

    assert_response :unprocessable_entity
    assert_match /categoría/, flash[:alert].to_s
  end

  test "POST confirm renders the review without creating expenses when nothing is selected" do
    assert_no_difference -> { Expense.count } do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: [ { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01", selected: "0" } ]
      }
    end

    assert_response :success
    assert_select "td", text: /Restaurante XYZ/
  end

  # ------------------------------------------------------------------- pay
  test "POST pay registers the payment and returns to the money source" do
    assert_difference -> { Payment.count }, 1 do
      post pay_money_source_statement_imports_path(@card), params: {
        payment: { register: "1", amount: "63000", date: "2026-09-05", description: "Pago Visa",
                   category_id: @category.id, principal_amount: "60000", interest_amount: "3000",
                   funding_money_source_id: @account.id }
      }
    end

    assert_redirected_to money_source_path(@card)
    payment = Payment.last
    assert_equal @card.id, payment.money_source_id
    assert_equal BigDecimal("60000"), payment.principal_amount
  end

  test "POST pay registers the payment even without a posted amount" do
    assert_difference -> { Payment.count }, 1 do
      post pay_money_source_statement_imports_path(@card), params: {
        payment: { register: "1", date: "2026-09-05", category_id: @category.id,
                   principal_amount: "60000", interest_amount: "3000",
                   funding_money_source_id: @account.id }
      }
    end

    assert_redirected_to money_source_path(@card)
    assert_equal BigDecimal("60000"), Payment.last.principal_amount
  end

  test "POST pay re-renders the review and creates nothing when the payment fails" do
    assert_no_difference -> { Payment.count } do
      post pay_money_source_statement_imports_path(@card), params: {
        summary: @document.summary.to_h.to_json,
        payment: { register: "1", amount: "63000", date: "2026-09-05",
                   principal_amount: "60000", interest_amount: "3000" }
      }
    end

    assert_response :unprocessable_entity
    assert_match /categoría/, flash[:alert].to_s
  end

  test "POST pay rejects a funding source that cannot pay (a loan)" do
    loan = @user.money_sources.create!(name: "Crédito carro", kind: "loan", sub_kind: "vehicle",
                                       starting_balance: 0)

    assert_no_difference -> { Payment.count } do
      post pay_money_source_statement_imports_path(@card), params: {
        payment: { register: "1", amount: "63000", date: "2026-09-05", description: "Pago Visa",
                   category_id: @category.id, principal_amount: "60000",
                   funding_money_source_id: loan.id }
      }
    end

    assert_response :unprocessable_entity
  end

  test "the funding select offers only payment sources and excludes the paid debt" do
    loan = @user.money_sources.create!(name: "Crédito carro", kind: "loan", sub_kind: "vehicle",
                                       starting_balance: 0)
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "select[name='payment[funding_money_source_id]'] option[value='#{@account.id}']"
    assert_select "select[name='payment[funding_money_source_id]'] option[value='#{loan.id}']", 0
    assert_select "select[name='payment[funding_money_source_id]'] option[value='#{@card.id}']", 0
  end

  test "review omits the payment form when the payment was already registered" do
    funding = @user.money_sources.create!(name: "Ahorros pago", kind: "account", starting_balance: 0)
    expense = Expense.create!(user: @user, amount: 500_000, description: "Pago Visa",
                              date: Date.new(2026, 8, 24), kind: "expense", source: "statement_file",
                              money_source: funding)
    Payment.create!(user: @user, expense: expense, money_source: @card, amount: 500_000,
                    principal_amount: 500_000)
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "form[data-payment-distribution-form='true']", 0
    assert_select "form[data-movement-form='true']", 1
  end

  test "POST pay responds with JSON success (progressive request)" do
    assert_difference -> { Payment.count }, 1 do
      post pay_money_source_statement_imports_path(@card), as: :json, params: {
        payment: { register: "1", amount: "63000", date: "2026-09-05", description: "Pago Visa",
                   category_id: @category.id, principal_amount: "60000", interest_amount: "3000",
                   funding_money_source_id: @account.id }
      }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert body["notice"].present?
  end

  test "POST pay responds with JSON errors and creates nothing when the payment fails" do
    assert_no_difference -> { Payment.count } do
      post pay_money_source_statement_imports_path(@card), as: :json, params: {
        payment: { register: "1", amount: "63000", date: "2026-09-05" }
      }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert body["errors"].any?
  end

  test "review renders the control hooks the movement JS binds to" do
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "[data-movement-bulk-open]", 1
    assert_select "#bulkCategoryModal [data-movement-bulk-category]", 1
    assert_select "#bulkCategoryModal [data-movement-bulk-apply]", 1
    assert_select "[data-movement-pay-only]", 1
    assert_select "[data-movement-selection-count]", 1
    assert_select "[data-movement-error]"
  end

  # --------------------------------------------------- category safety
  test "review renders a per-row category select and a payment category select" do
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "select[name*='[category_id]']"
    assert_select "select[name='payment[category_id]']"
  end

  test "review splits the movements and payment into separate forms" do
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "form[data-movement-form='true']", 1
    assert_select "form[data-payment-distribution-form='true']", 1
    assert_select "#statement-summary", 1
    assert_select "#statement-payment-form", 1
    # The movements form no longer carries the payment registration checkbox.
    assert_select "form[data-movement-form='true'] input[name='payment[register]']", 0
    assert_select "form[data-movement-form='true'] input[type='submit'][value=?]", I18n.t("statement_imports.confirm")
    assert_select "form[data-payment-distribution-form='true'] [data-payment-submit]", 1
    assert_select "form[data-payment-distribution-form='true'] [data-payment-submit]", text: I18n.t("statement_imports.payment_submit")
    assert_select "form[data-payment-distribution-form='true'] [data-payment-spinner].spinner-border", 1
  end


  # ----------------------------------------------- engine badge (adapter path)
  test "POST create renders the learned-parser badge and summary for an adapter document" do
    document = Statements::Document.new(
      engine: :adapter,
      summary: Statements::Summary.new(total_due: "3983689", due_date: "2026-10-07"),
      movements: [ { date: "2026-09-10", description: "SMART FIT", amount: 112_916, type: "expense" } ]
    )

    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "span.badge", text: /Parser directo/
    assert_select "form[data-payment-distribution-form='true']", 1
    assert_select "td", text: /Total a pagar/ # summary table rendered from the learned recipe
  end

  test "POST confirm keeps the learned-parser badge from the posted engine" do
    post confirm_money_source_statement_imports_path(@card), params: {
      engine: "adapter",
      summary: Statements::Summary.new(total_due: "1000").to_h.to_json,
      movements: [ { description: "Café", amount: "5000", date: "2026-09-01",
                     category_id: @category.id, selected: "1" } ]
    }

    assert_response :success
    assert_select "span.badge", text: /Parser directo/
  end

  test "review renders the group controls, bulk modal and pay-only toggle" do
    document = @document
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.success(document) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }
      assert_response :success
    end

    assert_select "form[data-movement-form='true'] [data-movement-select-all]", 1
    assert_select "form[data-movement-form='true'] [data-movement-bulk-open]", 1
    assert_select "form[data-movement-form='true'] input[name='engine']", 1
    assert_select "#bulkCategoryModal [data-movement-bulk-category]", 1
    assert_select "#bulkCategoryModal [data-movement-bulk-apply]", 1
    assert_select "form[data-movement-form='true'] [data-movement-pay-only]", 1
    assert_select "[data-movement-pay-only-hint]", 1
  end


  test "confirm never parks movements without a usable category as review candidates" do
    assert_no_difference -> { Expense.count } do
      assert_no_difference -> { ExpenseCandidate.count } do
        post confirm_money_source_statement_imports_path(@card), params: {
          movements: [ { description: "MAXIDIFICACION RARA", amount: "48500", date: "2026-09-01",
                         money_source_id: @card.id, selected: "1" } ]
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "confirm with a row the user classified creates the expense directly" do
    assert_difference -> { Expense.count }, 1 do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: [ { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01",
                       category_id: @category.id, selected: "1" } ]
      }
    end

    assert_response :success
  end

  test "confirm skips movements that duplicate an existing expense and reports it" do
    Expense.create!(user: @user, category: @category, money_source: @card,
                    amount: -48_500, date: Date.new(2026, 9, 1), description: "Restaurante XYZ")

    assert_no_difference -> { Expense.count } do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: [ { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01",
                       category_id: @category.id, money_source_id: @card.id, selected: "1" } ]
      }
    end

    assert_response :success
    assert_match /duplicado omitido/, flash[:notice].to_s
  end

  test "POST confirm lowers the money source balance and POST pay applies the payment" do
    card_before = @card.reload.balance
    account_before = @account.reload.balance

    post confirm_money_source_statement_imports_path(@card), params: {
      summary: @document.summary.to_h.to_json,
      movements: {
        "0" => { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01",
                 category_id: @category.id, selected: "1" },
        "1" => { description: "Supermercado", amount: "15000", date: "2026-09-02",
                 category_id: @category.id, selected: "1" }
      }
    }
    assert_response :success

    post pay_money_source_statement_imports_path(@card), params: {
      payment: { register: "1", date: "2026-09-05", category_id: @category.id,
                 principal_amount: "60000",
                 interest_amount: "3000", funding_money_source_id: @account.id }
    }
    assert_redirected_to money_source_path(@card)

    # 63,500 of purchases, 60,000 paid in principal: the card keeps only the
    # 3,000 interest owed.
    assert_equal card_before - 63_500 + 60_000, @card.reload.balance
    assert_equal BigDecimal("3500"), @card.reload.used_credit
    assert_equal account_before - 63_000, @account.reload.balance
  end

  private

  def uploaded_file(content, name)
    file = Tempfile.new(File.basename(name))
    file.binmode
    file.write(content)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: name, type: "application/pdf")
  end
end
