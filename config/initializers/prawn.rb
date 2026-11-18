# frozen_string_literal: true

# Statement PDFs use Prawn's built-in fonts and convert dynamic text to
# Windows-1252 before drawing (see StatementExports::Pdf#pdf_text), so the
# library's UTF-8 warning is redundant.
Prawn::Fonts::AFM.hide_m17n_warning = true
