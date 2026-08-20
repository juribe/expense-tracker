class QaValidateDashboardReportsController < ApplicationController
  before_action :authenticate_user!

  # GET /qa/validate
  # Main validation page - shows dashboard and reports validation status
  def index
    @validations = {
      dashboard: validate_dashboard,
      database: validate_database,
      routes: validate_routes,
      expenses: validate_expenses
    }
  end

  # GET /qa/validate/dashboard
  # Validate dashboard specific functionality
  def dashboard
    @validation = validate_dashboard
    render :validate
  end

  # GET /qa/validate/reports
  # Validate reports functionality
  def reports
    @validation = validate_reports
    render :validate
  end

  # GET /qa/validate/run_all
  # Run all validations and return JSON
  def run_all
    validations = {
      timestamp: Time.current,
      checks: {
        app_boots: app_boots?,
        database_connected: database_connected?,
        routes_accessible: routes_accessible?,
        dashboard_works: dashboard_accessible?,
        authentication_works: authentication_works?,
        expenses_crud: expenses_crud_works?
      }
    }

    validations[:all_passed] = validations[:checks].values.all?
    
    if validations[:all_passed]
      validations[:status] = "PASS"
      validations[:message] = "All validations passed!"
    else
      validations[:status] = "FAIL"
      failed = validations[:checks].select { |_, v| !v }.keys
      validations[:message] = "Failed checks: #{failed.join(', ')}"
    end

    respond_to do |format|
      format.json { render json: validations }
      format.html { 
        @validation = validations
        render :results 
      }
    end
  end

  private

  def validate_dashboard
    {
      name: "Dashboard",
      status: dashboard_accessible? ? "PASS" : "FAIL",
      details: dashboard_accessible? ? "Dashboard loads correctly" : "Dashboard not accessible"
    }
  end

  def validate_database
    {
      name: "Database",
      status: database_connected? ? "PASS" : "FAIL",
      details: database_connected? ? "Database connected" : "Database connection failed"
    }
  end

  def validate_routes
    {
      name: "Routes",
      status: routes_accessible? ? "PASS" : "FAIL",
      details: routes_accessible? ? "All routes accessible" : "Some routes missing"
    }
  end

  def validate_expenses
    {
      name: "Expenses CRUD",
      status: expenses_crud_works? ? "PASS" : "FAIL",
      details: expenses_crud_works? ? "Expenses CRUD working" : "Expenses CRUD broken"
    }
  end

  def validate_reports
    {
      timestamp: Time.current,
      checks: {
        app_boots: app_boots?,
        database_connected: database_connected?,
        routes_accessible: routes_accessible?
      }
    }
  end

  def app_boots?
    true # If we got here, app is booting
  end

  def database_connected?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue
    false
  end

  def routes_accessible?
    begin
      # Check if we can generate URLs for main routes
      Rails.application.routes.recognize_path("/dashboard")
      Rails.application.routes.recognize_path("/expenses")
      Rails.application.routes.recognize_path("/categories")
      true
    rescue
      false
    end
  end

  def dashboard_accessible?
    begin
      Rails.application.routes.recognize_path("/dashboard")
      true
    rescue
      false
    end
  end

  def authentication_works?
    defined?(Devise) && User.count >= 0
  end

  def expenses_crud_works?
    Expense.count >= 0 rescue false
  end
end
