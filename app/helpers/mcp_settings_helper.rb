# frozen_string_literal: true

# McpSettingsHelper
# Presentation helpers for the MCP connections page.
#
# Example: mcp_config_example_json("https://yogasto.co/mcp")
module McpSettingsHelper
  def mcp_config_example(endpoint_url)
    {
      "mcpServers" => {
        "yogasto" => {
          "url" => endpoint_url,
          "headers" => {
            "Authorization" => "Bearer TU_TOKEN"
          }
        }
      }
    }
  end

  def mcp_config_example_json(endpoint_url)
    JSON.pretty_generate(mcp_config_example(endpoint_url))
  end

  def mcp_config_example_html(endpoint_url)
    escaped = ERB::Util.html_escape(mcp_config_example_json(endpoint_url))
    highlighted = escaped.gsub(/(&quot;.*?&quot;)(\s*:)?/) do
      string = Regexp.last_match(1)
      separator = Regexp.last_match(2)
      css = separator ? "mcp-code-key" : "mcp-code-string"
      %(<span class="#{css}">#{string}</span>#{separator})
    end

    highlighted.html_safe
  end

  def mcp_scope_badge(scope)
    css = scope == "write" ? "warning" : "primary"
    content_tag(:span, t("mcp.settings.scope_#{scope}"), class: "badge rounded-pill bg-#{css}-subtle text-#{css} mcp-badge")
  end

  def mcp_status_badge(token)
    label, css = mcp_status_for(token)

    content_tag(:span, class: "badge rounded-pill bg-#{css}-subtle text-#{css} mcp-badge") do
      safe_join([ content_tag(:i, "", class: "ti ti-point-filled me-1"), label ])
    end
  end

  def mcp_prompt_text(endpoint_url, key = "TU_TOKEN")
    <<~PROMPT
      Quiero conectar Yogasto como servidor MCP en este entorno.

      Configura la conexión usando estos datos:

      - Nombre: Yogasto
      - Dirección del servidor: #{endpoint_url}
      - Método de autenticación: Bearer Token
      - Clave de conexión: #{key}

      Detecta qué asistente o cliente estoy utilizando y aplica el mecanismo recomendado para configurar servidores MCP en ese entorno.

      Puede ser OpenCode, Claude Code, Cursor, VS Code, ChatGPT u otra herramienta compatible.

      Requisitos:

      1. Identifica automáticamente el entorno en el que estás trabajando.
      2. Configura Yogasto como servidor MCP utilizando los datos proporcionados.
      3. Utiliza el método de autenticación Bearer Token.
      4. Si necesitas modificar archivos de configuración, conserva todas las configuraciones existentes.
      5. No sobrescribas ni elimines otros servidores MCP.
      6. Verifica que la conexión funcione y que las herramientas de Yogasto estén disponibles.
      7. Si necesitas una autorización o acción manual, explícame exactamente qué debo hacer.
      8. No expongas la clave en archivos públicos, logs, repositorios o mensajes innecesarios.
    PROMPT
  end

  private

  def mcp_status_for(token)
    return [ t("mcp.settings.revoked"), "danger" ] if token.revoked?
    return [ t("mcp.settings.expired"), "secondary" ] if token.expired?

    [ t("mcp.settings.active"), "success" ]
  end
end
