class CategoriesController < ApplicationController
  before_action :set_category, only: [:show, :edit, :update, :destroy]
  before_action :set_parent_categories, only: [:new, :create, :edit, :update]

  # GET /categories
  def index
    @default_categories = Category.defaults
    @custom_categories = Category.custom_for_user(current_user)
  end

  # GET /categories/1
  def show
  end

  # GET /categories/new
  def new
    @category = Category.new(is_default: false)
  end

  # GET /categories/1/edit
  def edit
    unless @category.editable_by?(current_user)
      redirect_to categories_path, alert: "You can only edit your own categories."
      return
    end
  end

  # POST /categories
  def create
    @category = Category.new(category_params)
    @category.user = current_user
    @category.is_default = false
    respond_to do |format|
      if @category.save
        format.html { redirect_to @category, flash: { success: "Category was successfully created." } }
        format.json { render :show, status: :created, location: @category }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /categories/1
  def update
    unless @category.editable_by?(current_user)
      redirect_to categories_path, alert: "You can only edit your own categories."
      return
    end

    respond_to do |format|
      if @category.update(category_params)
        format.html { redirect_to @category, flash: { success: "Category was successfully updated." } }
        format.json { render :show, status: :ok, location: @category }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @category.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /categories/1
  def destroy
    unless @category.deletable_by?(current_user)
      redirect_to categories_path, alert: "You can only delete your own categories."
      return
    end

    @category.destroy
    respond_to do |format|
      format.html { redirect_to categories_url, flash: { success: "Category was successfully destroyed." } }
      format.json { head :no_content }
    end
  end

  private

  def set_category
    @category = Category.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Category not found."
    redirect_to categories_path
  end

  def set_parent_categories
    @parent_categories = Category.for_user(current_user).order(:name)
  end

  def category_params
    params.require(:category).permit(:name, :slug, :parent_id, :description, :active, :image, :category_type)
  end
end
