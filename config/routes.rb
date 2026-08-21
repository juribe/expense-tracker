# config/routes.rb
Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise authentication
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    passwords: 'users/passwords'
  }

  # Allow sign out via GET as a no-JS fallback (Turbo/JS may not be loaded)
  devise_scope :user do
    get "users/sign_out", to: "devise/sessions#destroy", as: :user_session_sign_out_get
  end

  # QA Validation routes
  get 'qa/validate', to: 'qa_validate_dashboard_reports#index'
  get 'qa/validate/dashboard', to: 'qa_validate_dashboard_reports#dashboard'
  get 'qa/validate/reports', to: 'qa_validate_dashboard_reports#reports'
  get 'qa/validate/run_all', to: 'qa_validate_dashboard_reports#run_all'

  # Resources
  resources :expenses do
    collection do
      delete :bulk_destroy
    end
  end
  resources :categories
  resources :monthly_reports, only: [:index, :show]
  # CRUD happens on the index page via modals, so new/edit/show are not exposed.
  resources :recurring_transactions, except: [:new, :edit, :show] do
    member do
      post :process_transaction
      patch :toggle_active
    end
  end

  # Dashboard
  get 'dashboard', to: 'dashboard#index'

  # Root route
  root to: 'dashboard#index'
end
