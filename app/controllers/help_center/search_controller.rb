# HelpCenter::SearchController
# GET /ayuda/buscar
# Public JSON search for the help center. HTML requests fall back to the
# Maglev landing page with the query string.
class HelpCenter::SearchController < ApplicationController
  skip_before_action :authenticate_user!, only: :index
  skip_before_action :require_membership_selection, only: :index

  def index
    @query = params[:q].to_s.strip
    @results = HelpCenter::Search.new(query: @query).call

    respond_to do |format|
      format.json { render json: json_payload }
      format.html { redirect_to "/ayuda?#{ { q: @query }.to_query }" }
    end
  end

  private

  def json_payload
    {
      query: @query,
      total: @results.size,
      results: @results.map { |article| result_payload(article) },
      message: @results.empty? ? I18n.t("help_center.search.empty") : nil
    }.compact
  end

  def result_payload(article)
    {
      title: article.title,
      category: article.category_name,
      summary: article.summary,
      url: article.url
    }
  end
end
