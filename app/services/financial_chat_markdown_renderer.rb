# frozen_string_literal: true

require "cgi"
require "json"

# FinancialChatMarkdownRenderer
# Renders the assistant's markdown subset to safe HTML. All input is
# HTML-escaped first; only an allowlist of constructs is converted:
#
#   paragraphs (soft breaks), **bold**, *italic*, `code`,
#   "- " bullets, "1. " ordered lists, "## " headings,
#   simple pipe tables, and ```insight fenced blocks carrying
#   structured financial cards (JSON: title/value/delta/detail/rows).
#
#   FinancialChatMarkdownRenderer.render("Gastaste **COP 845.000** en restaurantes")
class FinancialChatMarkdownRenderer
  INSIGHT_ALLOWED_KEYS = %w[title value delta detail rows].freeze
  INSIGHT_ROW_KEYS = %w[label value].freeze
  FENCED_OPENER = /\A```(\w*)\s*\z/
  # Block openers that end a plain paragraph.
  PARAGRAPH_STOP = /\A(```|\||\s*[-*] |\s*\d+\. |\#{1,3}\s)/

  def self.render(text)
    new(text).call
  end

  def initialize(text)
    @text = text.to_s
  end

  def call
    return "" if @text.strip.empty?

    html = +""
    lines = @text.lines.map(&:chomp)
    index = 0

    while index < lines.size
      line = lines[index]

      if (fence = line.match(FENCED_OPENER))
        html << consume_fenced_block(lines, index + 1, fence[1]) { |next_index| index = next_index }
      elsif table?(lines, index)
        html << consume_table(lines, index) { |next_index| index = next_index }
      elsif (list = line.match(/\A\s*[-*] /))
        html << consume_list(lines, index, :ul) { |next_index| index = next_index }
      elsif line.match(/\A\s*\d+\. /)
        html << consume_list(lines, index, :ol) { |next_index| index = next_index }
      elsif (heading = line.match(/\A\#{1,3}\s+(.+)\z/))
        html << %(<p class="chat-md-heading"><strong>#{inline(heading[1])}</strong></p>)
        index += 1
      elsif line.strip.empty?
        index += 1
      else
        html << consume_paragraph(lines, index) { |next_index| index = next_index }
      end
    end

    html
  end

  private

  def consume_fenced_block(lines, start, language)
    content = []
    index = start
    index += 1 while index < lines.size && !lines[index].start_with?("```")

    if index < lines.size
      yield index + 1
      content = lines[start...index]
    else
      yield index
      content = lines[start..]
    end

    if language == "insight"
      insight_card(content.join("\n"))
    else
      render_pre(content)
    end
  end

  def table?(lines, index)
    lines[index].strip.start_with?("|") &&
      lines[index + 1].to_s.match?(/\A\|?[\s|:-]+\|\z/) &&
      lines[index + 1].to_s.include?("-")
  end

  def consume_table(lines, start)
    rows = []
    index = start
    index += 1 while index < lines.size && lines[index].strip.start_with?("|")

    body_rows = lines[start...index].reject { |row| row.match?(/\A\|?[\s|:-]+\|\z/) }
    body_rows.each do |row|
      cells = row.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip)
      rows << cells
    end

    yield index
    return "" if rows.empty?

    header, *body = rows
    html = +%(<table class="chat-md-table"><thead><tr>)
    header.each { |cell| html << "<th>#{inline(cell)}</th>" }
    html << "</tr></thead><tbody>"
    body.each do |cells|
      html << "<tr>"
      cells.each { |cell| html << "<td>#{inline(cell)}</td>" }
      html << "</tr>"
    end
    html << "</tbody></table>"
  end

  def consume_list(lines, start, tag)
    items = []
    pattern = tag == :ul ? /\A\s*[-*] (.*)\z/ : /\A\s*\d+\. (.*)\z/
    index = start
    index += 1 while index < lines.size && lines[index].match?(pattern)

    lines[start...index].each { |line| items << line.match(pattern)[1] }

    yield index
    html = +"<#{tag} class=\"chat-md-list\">"
    items.each { |item| html << "<li>#{inline(item)}</li>" }
    html << "</#{tag}>"
  end

  def consume_paragraph(lines, start)
    paragraph = []
    index = start
    index += 1 while index < lines.size && !lines[index].strip.empty? &&
                     !lines[index].match?(PARAGRAPH_STOP)

      paragraph = lines[start...index]
      yield index
      "<p>#{paragraph.map { |line| inline(line) }.join("<br>")}</p>"
  end

  def inline(text)
    escaped = CGI.escapeHTML(text)
    escaped = escaped.gsub(/`([^`]+)`/) { %(<code>#{Regexp.last_match(1)}</code>) }
    escaped = escaped.gsub(/\*\*([^*]+)\*\*/) { %(<strong>#{Regexp.last_match(1)}</strong>) }
    escaped.gsub(/(^|[\s(])\*([^*\s][^*]*)\*/) { "#{Regexp.last_match(1)}<em>#{Regexp.last_match(2)}</em>" }
  end

  def render_pre(content_lines)
    content = content_lines.join("\n")
    %(<pre class="chat-md-pre"><code>#{CGI.escapeHTML(content)}</code></pre>)
  end

  # ```insight { "title": ..., "value": ..., "delta": ..., "detail": ...,
  #              "rows": [{ "label": ..., "value": ... }] } ```
  # → a compact financial card. Invalid payloads degrade to a code block.
  def insight_card(json)
    data = JSON.parse(json)
    return render_pre([ json ]) unless data.is_a?(Hash) && (data.keys - INSIGHT_ALLOWED_KEYS).empty?

    html = +%(<div class="chat-insight">)
    html << %(<div class="chat-insight-title">#{CGI.escapeHTML(data["title"].to_s)}</div>) if data["title"]
    html << %(<div class="chat-insight-value">#{CGI.escapeHTML(data["value"].to_s)}</div>) if data["value"]
    html << %(<div class="chat-insight-delta">#{CGI.escapeHTML(data["delta"].to_s)}</div>) if data["delta"]
    if data["rows"].is_a?(Array) && data["rows"].all? { |row| row.is_a?(Hash) && (row.keys - INSIGHT_ROW_KEYS).empty? }
      html << %(<ul class="chat-insight-rows">)
      data["rows"].each do |row|
        html << %(<li><span>#{CGI.escapeHTML(row["label"].to_s)}</span><strong>#{CGI.escapeHTML(row["value"].to_s)}</strong></li>)
      end
      html << "</ul>"
    end
    html << %(<div class="chat-insight-detail">#{CGI.escapeHTML(data["detail"].to_s)}</div>) if data["detail"]
    html << "</div>"
    html
  rescue JSON::ParserError, TypeError
    render_pre([ json ])
  end
end
