# frozen_string_literal: true

require "test_helper"

class SavingsOpportunitiesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @setting = PaymentEngine::Setting.current
    @setting.update!(paid_access_required: true)
    @membership_type = PaymentEngine::MembershipType.create!(
      name: "Savings Opportunities Test",
      code: "SAVINGS_OPPS_#{SecureRandom.hex(6)}",
      status: "active"
    )
    @user = User.create!(name: "Savings User", email: "savings_ops_ctrl@example.com", password: "password123")
    @category = Category.create!(name: "Restaurantes", is_default: true, category_type: "expense")
    @bank = @user.money_sources.create!(name: "Cuenta", kind: "account", active: true,
                                        starting_balance: 1_000_000_000)
    grant_premium
    sign_in @user
  end

  def grant_premium
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "active",
      source: "purchase",
      starts_at: 1.month.ago,
      expires_at: 1.month.from_now
    )
  end

  def revoke_premium
    PaymentEngine::Membership.where(owner: @user).delete_all
    PaymentEngine::Membership.create!(
      owner: @user,
      membership_type: @membership_type,
      status: "expired",
      source: "purchase",
      starts_at: 2.months.ago,
      expires_at: 1.day.ago
    )
  end

  def expense(amount, date: Date.current)
    Expense.create!(user: @user, category: @category, money_source: @bank,
                    amount: amount, date: date, description: "Restaurante")
  end

  test "Pro users can open the savings opportunities page" do
    [ 3, 2, 1 ].each { |months_ago| expense(-600_000, date: Date.current.months_ago(months_ago).beginning_of_month + 4.days) }
    expense(-900_000)

    get savings_opportunities_path

    assert_response :success
    assert_select "h1", text: "Oportunidades de ahorro"
    assert_select "title", "Oportunidades de ahorro | #{AppName.current}"
    assert_match "Análisis inteligente de tus gastos", response.body
  end

  test "users without the Pro plan are redirected with the premium alert" do
    revoke_premium

    get savings_opportunities_path

    assert_redirected_to dashboard_path
    assert_equal "Necesitas un plan premium para utilizar esta función.", flash[:alert]
  end

  test "users without the Pro plan cannot use the refresh endpoint" do
    revoke_premium

    post refresh_savings_opportunities_path

    assert_redirected_to dashboard_path
  end

  test "users without the Pro plan cannot use the scenario endpoint" do
    revoke_premium

    post scenario_savings_opportunities_path, params: { reductions: {} }

    assert_redirected_to dashboard_path
  end

  test "users without the Pro plan cannot read the analysis status" do
    revoke_premium

    get status_savings_opportunities_path

    assert_redirected_to dashboard_path
  end

  test "shows the empty state without movements" do
    get savings_opportunities_path

    assert_response :success
    assert_match "Aún no hay movimientos suficientes", response.body
  end

  test "renders the four sections with real data" do
    [ 3, 2, 1 ].each { |months_ago| expense(-600_000, date: Date.current.months_ago(months_ago).beginning_of_month + 4.days) }
    expense(-900_000)
    [ 3, 2, 1, 0 ].each { |months_ago| expense(-29_900, date: Date.current.months_ago(months_ago).beginning_of_month + 11.days) }

    get savings_opportunities_path

    assert_response :success
    assert_match "Dónde gastar menos", response.body
    assert_match "Gastos recurrentes", response.body
    assert_match "Pequeños gastos", response.body
    assert_match "Simula cuánto podrías ahorrar", response.body
  end

  test "renders when there are no recurring patterns or small expenses" do
    expense(-50_000, date: Date.current.beginning_of_month)

    get savings_opportunities_path

    assert_response :success
    assert_match "Gastos recurrentes", response.body
  end

  test "shows configured recurring payments when there is no previous-cycle history" do
    RecurringTemplate.create!(user: @user, category: @category, kind: "expense", description: "Netflix",
                              amount: 29_900, frequency: "monthly", source: "manual", payment_day: 12)
    expense(-50_000, date: Date.current.beginning_of_month)

    get savings_opportunities_path

    assert_response :success
    assert_match "Netflix", response.body
    assert_match "Configurado", response.body
    assert_match "pagos recurrentes que tienes configurados", response.body
    assert_match "Total configurado", response.body
    assert_select "a[href=?]", monthly_expenses_path, text: "Revisar mis pagos recurrentes"
  end

  test "refresh enqueues the AI analysis only when AI is available" do
    with_test_queue_adapter do
      with_env("MISTRAL_API_KEY" => "test-key") do
        assert_enqueued_with(job: SavingsOpportunityAnalysisJob, args: [ @user.id ]) do
          post refresh_savings_opportunities_path, as: :json
        end
      end
    end

    assert_response :accepted
    assert_equal "pending", JSON.parse(response.body)["state"]
  end

  test "refresh does not enqueue when AI is not configured" do
    with_test_queue_adapter do
      assert_no_enqueued_jobs only: SavingsOpportunityAnalysisJob do
        post refresh_savings_opportunities_path, as: :json
      end
    end

    assert_response :ok
    assert_equal "unavailable", JSON.parse(response.body)["state"]
  end

  test "status reports the current analysis state" do
    get status_savings_opportunities_path, as: :json

    assert_response :success
    assert_includes %w[idle ready pending failed], JSON.parse(response.body)["state"]
  end

  test "status reports ready when the worker published the result" do
    with_analysis_cache do
      SavingsOpportunities::AnalysisState.write(@user.id, "ready")

      get status_savings_opportunities_path, as: :json

      assert_equal "ready", JSON.parse(response.body)["state"]
    end
  end

  test "status recovers from a stale pending analysis" do
    with_analysis_cache do
      SavingsOpportunities::AnalysisState.cache.write(
        SavingsOpportunities::AnalysisState.state_key(@user.id),
        { "state" => "pending", "at" => 10.minutes.ago.iso8601 }
      )

      get status_savings_opportunities_path, as: :json

      assert_equal "failed", JSON.parse(response.body)["state"]
    end
  end

  test "converting a scenario redirects to a prefilled goal" do
    [ 3, 2, 1 ].each { |months_ago| expense(-600_000, date: Date.current.months_ago(months_ago).beginning_of_month + 4.days) }
    expense(-900_000)

    post scenario_savings_opportunities_path, params: { reductions: { @category.id => "15" } }

    assert_response :redirect
    assert_includes response.location, "/goals/new"
    assert_includes response.location, "target_amount"
  end

  test "converting an empty scenario returns with an alert instead of creating a goal" do
    post scenario_savings_opportunities_path, params: { reductions: { @category.id => "0" } }

    assert_redirected_to savings_opportunities_path
    assert_equal "Selecciona al menos una reducción mayor que cero.", flash[:alert]
  end

  private

  def with_analysis_cache
    previous = SavingsOpportunities::AnalysisState.cache
    SavingsOpportunities::AnalysisState.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    SavingsOpportunities::AnalysisState.cache = previous
  end

  def with_test_queue_adapter
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    yield
  ensure
    ActiveJob::Base.queue_adapter = original
  end
end
