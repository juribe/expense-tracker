# frozen_string_literal: true

require "caxlsx"

module MoneySources
  module StatementExports
    # Renders a money source statement as an Excel workbook with one
    # "Movimientos" worksheet.
    class Xlsx < Base
      def call
        package = Axlsx::Package.new
        package.use_shared_strings = true

        workbook = package.workbook
        header_style = workbook.styles.add_style(b: true, bg_color: "E9ECEF")
        amount_style = workbook.styles.add_style(format_code: "#,##0.00", alignment: { horizontal: :right })

        workbook.add_worksheet(name: "Movimientos") do |sheet|
          sheet.add_row(HEADERS, style: header_style)
          movements.each do |movement|
            values = row(movement, amount: signed_amount(movement))
            sheet.add_row(values, style: [ nil, nil, nil, nil, nil, amount_style, nil ])
          end
          freeze_header(sheet)
          sheet.auto_filter = "A1:G#{sheet.rows.size}"
          sheet.column_widths 12, 38, 30, 22, 26, 16, 22
        end

        package.to_stream.read
      end

      private

      def extension
        "xlsx"
      end

      def freeze_header(sheet)
        sheet.sheet_view.pane do |pane|
          pane.top_left_cell = "A2"
          pane.state = :frozen
          pane.y_split = 1
          pane.active_pane = :bottom_left
        end
      end
    end
  end
end
