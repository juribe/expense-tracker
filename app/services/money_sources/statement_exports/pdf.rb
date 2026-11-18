# frozen_string_literal: true

require "prawn"
require "prawn/table"

module MoneySources
  module StatementExports
    # Renders a money source statement as PDF. The first page carries the
    # source summary and period totals; the movement table starts on a new
    # page so the summary stays a cover sheet.
    class Pdf < Base
      def call
        document = Prawn::Document.new(
          page_size: "A4",
          margin: [ 40, 40, 50, 40 ],
          info: { Title: pdf_text("Extracto #{source.name}"), Creator: "Yogasto" }
        )

        render_summary(document)
        document.start_new_page
        render_movements(document)
        document.number_pages "Página <page> de <total>", at: [ 0, -30 ], align: :right, size: 8
        document.render
      end

      private

      def extension
        "pdf"
      end

      def render_summary(document)
        document.text pdf_text(source.name.presence || source.display_name), size: 20, style: :bold
        document.move_down 12
        document.text "Resumen de la fuente", size: 13, style: :bold
        document.move_down 6
        render_rows(document, summary_rows)
        document.move_down 18
        document.text "Resumen del período", size: 13, style: :bold
        document.text statement.period_label, size: 9, color: "6B7280"
        document.move_down 6
        render_rows(document, period_rows)
      end

      def render_rows(document, rows)
        document.table(
          rows.map { |row| row.map { |cell| pdf_text(cell) } },
          width: document.bounds.width,
          column_widths: [ 150, document.bounds.width - 150 ],
          cell_style: { size: 10, padding: [ 5, 6 ], border_width: 0 }
        ) do |table|
          table.column(0).font_style = :bold
        end
      end

      def summary_rows
        [
          [ "Fuente", source.name.presence || source.display_name ],
          [ "Tipo", kind_label ],
          [ "Entidad", source.institution_name.presence || "—" ],
          [ "Estado", status_label ],
          [ "Saldo actual", money(current_balance) ]
        ]
      end

      def period_rows
        [
          [ "Saldo inicial", money(statement.opening_balance) ],
          [ statement.entries_label, money(statement.entries_total) ],
          [ statement.exits_label, money(statement.exits_total) ],
          [ "Saldo final del período", money(statement.closing_balance) ],
          [ "Cambio neto", money(statement.net_change) ]
        ]
      end

      def render_movements(document)
        document.text "Movimientos", size: 16, style: :bold
        document.move_down 8

        if movements.empty?
          document.text "No hay movimientos en este período.", size: 10, color: "6B7280"
          return
        end

        document.table(
          movement_rows,
          header: true,
          column_widths: [ 70, 215, 80, 80, 70 ],
          cell_style: { size: 8, padding: [ 4, 4 ], overflow: :shrink_to_fit }
        ) do |table|
          table.row(0).font_style = :bold
          table.row(0).background_color = "EEEEEE"
          table.column(4).align = :right
        end
      end

      def movement_rows
        [ [ "Fecha", "Descripción", "Categoría", "Tipo", "Monto" ] ] + movements.map do |movement|
          [
            movement.date.strftime("%d/%m/%Y"),
            movement_description(movement),
            pdf_text(movement.category&.name),
            pdf_text(movement.movement_type),
            signed_money(movement)
          ]
        end
      end

      def movement_description(movement)
        description = pdf_text(movement.description)
        return description if movement.secondary.blank?

        "#{description}\n#{pdf_text(movement.secondary)}"
      end

      def signed_money(movement)
        sign = movement.direction == "in" ? "+" : "-"
        "#{sign}#{money(movement.amount)}"
      end

      # Prawn's built-in fonts only cover Windows-1252. Replacing anything
      # outside that set keeps emoji or exotic bank descriptions from making
      # the whole export fail.
      def pdf_text(value)
        value.to_s
             .encode(Encoding.find("Windows-1252"), invalid: :replace, undef: :replace, replace: "?")
             .encode(Encoding::UTF_8)
      end
    end
  end
end
