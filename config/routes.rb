# config/routes.rb
Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions,
  # otherwise 500. Can be used by load balancers and uptime monitors to verify that
  # the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in
  # application.html.erb).  Uncomment the lines below if you want to expose them.
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Devise authentication
  devise_for :users

  # Resources
  resources :expenses
  resources :categories

  # QA validation endpoints
  namespace :qa do
    get   'validate',   to: 'qa#validate'      # GET  /qa/validate
    get   'dashboard',  to: 'qa#dashboard'     # GET  /qa/dashboard
    get   'reports',    to: 'qa#reports'       # GET  /qa/reports
  end

  # QA and validation endpoints
  get '/qa', to: 'qa#index'
  get '/validate', to: 'validate#index'

  # Dashboard and reports endpoints
  get '/dashboard', to: 'dashboard#index'
  get '/reports', to: 'reports#index'

  # Dashboard
  get 'dashboard', to: 'dashboard#index', as: :dashboard

  # Root route – points to the dashboards controller's index action
  root to: 'dashboards#index'
end