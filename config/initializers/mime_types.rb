# frozen_string_literal: true

# Rails does not register XLSX by default. The statement export exposes it as
# /money_sources/:id/extractos.xlsx.
Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx
