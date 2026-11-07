# frozen_string_literal: true

require "test_helper"

# Public article rating endpoint. Visitors can rate anonymously; the same
# visitor cannot create duplicate rows for the same article.
class HelpCenterRatingsControllerTest < ActionDispatch::IntegrationTest
  include PublicCmsTestSupport
  include HelpCenterTestSupport

  setup do
    create_maglev_site!
    create_help_category_index!
    @article = create_help_article_index!
  end

  test "un voto anónimo registra una valoración y agradece" do
    assert_difference -> { HelpArticleRating.count }, 1 do
      post "/ayuda/valoracion",
           params: { page_id: @article.maglev_page_id, helpful: "true" },
           as: :json
    end

    assert_response :success
    data = JSON.parse(response.body)
    assert_equal true, data["ok"]
    assert data["message"].present?
  end

  test "un voto duplicado no crea otra fila y sigue agradeciendo" do
    params = { page_id: @article.maglev_page_id, helpful: "true" }

    assert_difference -> { HelpArticleRating.count }, 1 do
      post "/ayuda/valoracion", params: params, as: :json
      post "/ayuda/valoracion", params: params, as: :json
    end

    assert_response :success
    assert_equal true, JSON.parse(response.body)["ok"]
  end

  test "un voto a un artículo no publicado responde 404" do
    post "/ayuda/valoracion",
         params: { page_id: SecureRandom.uuid, helpful: "true" },
         as: :json

    assert_response :not_found
  end

  test "un valor de valoración inválido responde 422" do
    post "/ayuda/valoracion",
         params: { page_id: @article.maglev_page_id, helpful: "quizás" },
         as: :json

    assert_response :unprocessable_entity
    data = JSON.parse(response.body)
    assert_equal false, data["ok"]
    assert data["error"].present?
  end

  test "el rate limiting bloquea ráfagas por IP" do
    with_memory_cache do
      10.times do
        post "/ayuda/valoracion",
             params: { page_id: @article.maglev_page_id, helpful: "true" },
             as: :json
      end

      post "/ayuda/valoracion",
           params: { page_id: @article.maglev_page_id, helpful: "true" },
           as: :json
    end

    assert_response :too_many_requests
    assert_equal false, JSON.parse(response.body)["ok"]
  end

  test "el fallback HTML redirige al artículo" do
    post "/ayuda/valoracion",
         params: { page_id: @article.maglev_page_id, helpful: "true" }

    assert_redirected_to "/ayuda/primeros-pasos/crear-cuenta"
  end

  test "la respuesta no expone conteos internos" do
    post "/ayuda/valoracion",
         params: { page_id: @article.maglev_page_id, helpful: "true" },
         as: :json

    data = JSON.parse(response.body)
    assert_equal %w[message ok], data.keys.sort
  end

  private

  def with_memory_cache
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield
  ensure
    Rails.cache = original_cache
  end
end
