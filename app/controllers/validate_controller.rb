class ValidateController < ApplicationController
  # GET /validate
  def index
    # Simple validation: ensure we can query the database.
    ActiveRecord::Base.connection.execute('SELECT 1')
    render json: { status: 'ok', message: 'Validation passed' }, status: :ok
  rescue ActiveRecord::ActiveRecordError => e
    render json: { status: 'error', message: "Database validation failed: #{e.message}" }, status: :service_unavailable
  rescue StandardError => e
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end
end