# spec/requests/categories_spec.rb
require 'rails_helper'

RSpec.describe "Categories", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /categories" do
    it "returns a successful response" do
      get categories_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /categories/:id" do
    let(:category) { create(:category) }

    it "assigns the requested category and renders show template" do
      get category_path(category)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(category.name)
    end
  end

  describe "GET /categories/new" do
    it "renders the new template" do
      get new_category_path
      expect(response).to render_template(:new)
    end
  end

  describe "POST /categories" do
    context "with valid params" do
      it "creates a new category and redirects" do
        expect {
          post categories_path, params: { category: { name: "Travel", description: "Travel expenses" } }
        }.to change(Category, :count).by(1)

        expect(response).to redirect_to(categories_path)
        expect(flash[:notice]).to eq("Category was successfully created.")
      end
    end

    context "with invalid params" do
      it "renders the new template" do
        post categories_path, params: { category: { name: "" } }
        expect(response).to render_template(:new)
      end
    end
  end

  describe "GET /categories/:id/edit" do
    let(:category) { create(:category) }

    it "renders the edit template" do
      get edit_category_path(category)
      expect(response).to render_template(:edit)
    end
  end

  describe "PATCH /categories/:id" do
    let(:category) { create(:category, name: "Old Name", description: "Old Desc") }

    context "with valid params" do
      it "updates the category and redirects" do
        patch category_path(category), params: { category: { name: "Updated", description: "Updated Desc" } }
        expect(response).to redirect_to(categories_path)
        expect(flash[:notice]).to eq("Category was successfully updated.")
      end
    end

    context "with invalid params" do
      it "renders the edit template" do
        patch category_path(category), params: { category: { name: "" } }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe "DELETE /categories/:id" do
    let(:category) { create(:category) }

    it "destroys the category and redirects" do
      expect {
        delete category_path(category)
      }.to change(Category, :count).by(-1)

      expect(response).to redirect_to(categories_path)
    end
  end
end