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
  resources :incomes
  resources :categories
  resources :recurring_templates do
    member do
      post :process_transaction
      post :toggle_active
    end
  end

  resources :monthly_incomes, only: [ :index, :create, :update, :destroy ] do
    member do
      post :process_transaction
      patch :toggle_active
    end
  end

  resources :monthly_expenses, only: [ :index, :create, :update, :destroy ] do
    member do
      post :process_transaction
      patch :toggle_active
    end
  end
  resources :monthly_reports, only: [:index, :show]

  resources :imports, only: [:new, :create]

  # Categories as the main entry point
  get 'dashboard', to: 'dashboard#index'
  root to: 'categories#index'
end
