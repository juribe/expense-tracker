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
      end
    end
  end

  test "POST create sends the parsed movements back for review" do
    document = @document
    review_params = {}
    spy = lambda do |user:, file_data:, filename:, password:|
      review_params.merge!(file_data: file_data, filename: filename, password: password)
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
  end

  test "POST create redirects back to the upload when parsing fails" do
    stub_method(Statements::Parser, :call, ->(**_kwargs) { ServiceResult.error([ "bad document" ]) }) do
      post money_source_statement_imports_path(@card), params: { file: "pdf-bytes", filename: "extracto.pdf" }

      assert_redirected_to new_money_source_statement_import_path(@card)
      assert_match /bad document/, flash[:alert].to_s
    end
  end

  # --------------------------------------------------------------- confirm
  test "POST confirm creates the selected movements and applies the payment" do
    assert_difference -> { Expense.count }, 2 do
      assert_difference -> { Payment.count }, 1 do
        post confirm_money_source_statement_imports_path(@card), params: {
          movements: [
            { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01", category_id: @category.id, selected: "1" },
            { description: "Supermercado", amount: "210000", date: "2026-09-02", category_id: @category.id, selected: "0" }
          ],
          payment: { register: "1", amount: "63000", date: "2026-09-05", description: "Pago Visa",
                     principal_amount: "60000", interest_amount: "3000",
                     funding_money_source_id: @account.id }
        }
      end
    end

    assert_redirected_to money_source_path(@card)
    assert_equal 1, Expense.where(source: "statement_file", description: "Restaurante XYZ").count
    payment = Payment.last
    assert_equal @card.id, payment.money_source_id
    assert_equal BigDecimal("60000"), payment.principal_amount

    get money_source_path(@card)
    assert_response :success
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

    assert_redirected_to money_source_path(@card)
    assert_equal 1, Expense.where(source: "statement_file", description: "Restaurante XYZ").count
  end

  test "POST confirm registers the payment even without a posted amount" do
    assert_difference -> { Payment.count }, 1 do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: {
          "0" => { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01",
                   category_id: @category.id, selected: "1" }
        },
        payment: { register: "1", date: "2026-09-05", principal_amount: "60000",
                   interest_amount: "3000", funding_money_source_id: @account.id }
      }
    end

    assert_redirected_to money_source_path(@card)
    payment = Payment.last
    assert_equal @card.id, payment.money_source_id
    assert_equal BigDecimal("60000"), payment.principal_amount
    assert_equal BigDecimal("3000"), payment.interest_amount
  end

  test "POST confirm redirects with no expenses when everything is unselected" do
    assert_no_difference -> { Expense.count } do
      post confirm_money_source_statement_imports_path(@card), params: {
        movements: [ { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01", selected: "0" } ],
        payment: { register: "0" }
      }
    end

    assert_redirected_to money_source_path(@card)
  end

  test "POST confirm re-renders the review and creates nothing when the payment fails" do
    assert_no_difference -> { Expense.count } do
      post confirm_money_source_statement_imports_path(@card), params: {
        summary: @document.summary.to_h.to_json,
        movements: [ { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01", selected: "1" } ],
        payment: { register: "1", amount: "63000", date: "2026-09-05",
                   principal_amount: "", interest_amount: "" }
      }
    end

    assert_response :unprocessable_entity
    assert_select "td", text: /Restaurante XYZ/
  end

  test "POST confirm lowers the money source balance for imported expenses" do
    card_before = @card.reload.balance
    account_before = @account.reload.balance

    post confirm_money_source_statement_imports_path(@card), params: {
      movements: {
        "0" => { description: "Restaurante XYZ", amount: "48500", date: "2026-09-01",
                 category_id: @category.id, selected: "1" },
        "1" => { description: "Supermercado", amount: "15000", date: "2026-09-02",
                 category_id: @category.id, selected: "1" }
      },
      payment: { register: "1", date: "2026-09-05", principal_amount: "60000",
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
