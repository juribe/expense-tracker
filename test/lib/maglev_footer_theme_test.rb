# frozen_string_literal: true

require "test_helper"

# The footer is a tree of columns; the editor only allows adding child blocks
# when the column definition declares which block types it accepts.
class MaglevFooterThemeTest < ActiveSupport::TestCase
  test "el bloque columna del footer acepta enlaces" do
    column = footer_section.blocks.find("column")

    assert_equal [ "link" ], column.accept
  end

  private

  def footer_section
    theme = Maglev::ThemeFilesystemLoader.new(
      ->(theme:, section:, absolute: true) { "theme/#{section.category}/#{section.id}.jpg" }
    ).call(Rails.root.join("app/theme"))

    theme.sections.find("footer")
  end
end
