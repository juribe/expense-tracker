# frozen_string_literal: true

require "test_helper"

class FinancialChatMarkdownRendererTest < ActiveSupport::TestCase
    def render(text)
      FinancialChatMarkdownRenderer.render(text)
    end

    test "escapes HTML injection attempts" do
      html = render("<script>alert('x')</script>")
      assert_not_includes html, "<script>"
      assert_includes html, "&lt;script&gt;"
    end

    test "renders paragraphs with soft breaks" do
      html = render("Primera línea\nSegunda línea")
      assert_includes html, "<p>Primera línea<br>Segunda línea</p>"
    end

    test "renders bold, italic and inline code" do
      html = render("**Restaurantes** *aumentó* `18%`")
      assert_includes html, "<strong>Restaurantes</strong>"
      assert_includes html, "<em>aumentó</em>"
      assert_includes html, "<code>18%</code>"
    end

    test "renders bullet lists" do
      html = render("Intro:\n- Uno\n- Dos\n\nCierre")
      assert_includes html, "<ul class=\"chat-md-list\">"
      assert_includes html, "<li>Uno</li>"
      assert_includes html, "<li>Dos</li>"
      assert_includes html, "<p>Cierre</p>"
    end

    test "renders ordered lists" do
      html = render("1. Primero\n2. Segundo")
      assert_includes html, "<ol class=\"chat-md-list\">"
      assert_includes html, "<li>Primero</li>"
      assert_includes html, "<li>Segundo</li>"
    end

    test "renders headings as bold paragraphs" do
      html = render("## Resumen")
      assert_includes html, "<strong>Resumen</strong>"
      assert_not_includes html, "<h2>"
    end

    test "renders pipe tables" do
      html = render("| Categoría | Total |\n| --- | --- |\n| Restaurantes | COP 845.000 |\n| Transporte | COP 420.000 |")
      assert_includes html, "<table"
      assert_includes html, "<th>Categoría</th>"
      assert_includes html, "<td>Restaurantes</td>"
      assert_includes html, "<td>COP 420.000</td>"
    end

    test "renders insight blocks as structured cards" do
      insight = { title: "Gasto mensual", value: "COP 4.820.000", delta: "+8.4% vs. mes anterior" }.to_json
      html = render("Respuesta\n\n```insight\n#{insight}\n```\n\nFin")

      assert_includes html, "chat-insight"
      assert_includes html, "Gasto mensual"
      assert_includes html, "COP 4.820.000"
      assert_includes html, "+8.4% vs. mes anterior"
    end

    test "insight rows render as label/value list" do
      insight = { title: "Top categorías", rows: [ { label: "Restaurantes", value: "COP 845.000" } ] }.to_json
      html = render("```insight\n#{insight}\n```")

      assert_includes html, "chat-insight-rows"
      assert_includes html, "Restaurantes"
      assert_includes html, "<strong>COP 845.000</strong>"
    end

    test "insight block with invalid JSON renders as code" do
      html = render("```insight\nno-json-here\n```")
      assert_includes html, "<pre"
      assert_includes html, "no-json-here"
    end

    test "insight fields are escaped" do
      insight = { title: "<script>x</script>", value: "COP 1" }.to_json
      html = render("```insight\n#{insight}\n```")
      assert_not_includes html, "<script>"
    end

    test "renders a complete financial answer" do
      html = render(<<~MD)
        Gastaste **COP 2.340.000** este mes.

        - Restaurantes: COP 845.000
        - Transporte: COP 420.000

        ¿Quieres que compare con el mes anterior?
      MD

      assert_includes html, "<strong>COP 2.340.000</strong>"
      assert_includes html, "<li>Restaurantes: COP 845.000</li>"
      assert_includes html, "¿Quieres que compare"
    end

    test "blank input renders empty" do
      assert_equal "", render("")
      assert_equal "", render(nil)
    end
  end
