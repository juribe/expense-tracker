class QaController < ApplicationController
  # GET /qa
  def index
    render json: { status: 'ok', message: 'QA endpoint reachable' }, status: :ok
  rescue StandardError => e
    render json: { status: 'error', message: e.message }, status: :internal_server_error
  end
end