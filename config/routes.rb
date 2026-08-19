# config/routes.rb
Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise authentication
  devise_for :users

  # Resources
  resources :expenses
  resources :categories

  # Dashboard
  get 'dashboard', to: 'dashboard#index'

  # Root route
  root to: 'dashboard#index'
end
