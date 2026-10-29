# frozen_string_literal: true

module CategoriesHelper
  # Clase de icono (`ti-*`) para una categoría. El icono estándar `ti-tag`
  # cubre categorías nuevas sin icono y datos históricos con `icon` nulo o
  # malformado, de modo que ningún request rompe por un icono faltante.
  def category_icon_klass(category, fallback: "ti-tag")
    icon = category&.icon.to_s.strip
    icon = fallback if icon.blank? || !icon.match?(/\Ati-[a-z0-9-]+\z/)
    "ti #{icon}"
  end

  # Renderiza el <i> del icono de una categoría, listo para usar en badges.
  def category_icon(category, fallback: "ti-tag", extra_class: nil)
    classes = [ category_icon_klass(category, fallback: fallback), extra_class ].compact.join(" ")
    tag.i(nil, class: classes, "aria-hidden": true)
  end
end
