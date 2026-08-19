# config/routes.rb
Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise authentication
  devise_for :users

  # QA Validation routes
  get 'qa/validate', to: 'qa_validate_dashboard_reports#index'
  get 'qa/validate/dashboard', to: 'qa_validate_dashboard_reports#dashboard'
  get 'qa/validate/reports', to: 'qa_validate_dashboard_reports#reports'
  get 'qa/validate/run_all', to: 'qa_validate_dashboard_reports#run_all'

  # Resources
  resources :expenses
  resources :categories

  # Dashboard
  get 'dashboard', to: 'dashboard#index'

  # Root route
  root to: 'dashboard#index'
end
