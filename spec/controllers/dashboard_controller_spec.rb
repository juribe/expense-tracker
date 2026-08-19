# spec/controllers/dashboard_controller_spec.rb
require 'rails_helper'

RSpec.describe DashboardController, type: :controller do
  # Assuming Devise for authentication
  include Devise::Test::ControllerHelpers

  let(:user) { create(:user) }
  let!(:expenses) { create_list(:expense, 3, user: user, amount: 10, created_at: Time.zone.today) }

  before { sign_in user }

  describe 'GET #index' do
    it 'responds successfully' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @summary' do
      get :index
      expect(assigns(:summary)).to be_a(Hash)
      expect(assigns(:summary)[:total_amount]).to eq(30)
    end

    context 'with invalid month param' do
      it 'falls back to current month and sets a flash alert' do
        get :index, params: { month: 'invalid-date' }
        expect(flash[:alert]).to be_present
        expect(assigns(:month)).to eq(Time.zone.today.to_date)
      end
    end
  end
end