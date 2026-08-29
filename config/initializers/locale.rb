# Localization defaults for the Colombian (COP) target market.
#
# - Spanish is the default language.
# - Dates and times render in the Bogota timezone.
# - Monetary values use Colombian formatting ($ symbol, "." thousands and
#   "," decimal separators) configured in config/locales/es.yml.
Rails.application.config.i18n.default_locale = :es
Rails.application.config.i18n.available_locales = %i[es en]
