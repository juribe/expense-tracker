# frozen_string_literal: true

module MoneySources
  module StatementExports
    # Shared behavior for the money source statement exporters: download
    # filenames, spreadsheet-safe text and signed movement amounts.
    class Base
      FORMULA_PREFIXES = %w[= + - @ \t \r].freeze
      HEADERS = [ "Fecha", "Descripción", "Detalle", "Categoría", "Tipo", "Monto", "Fuente relacionada" ].freeze

      def self.call(statement)
        new(statement).call
      end

      def self.filename(statement)
        new(statement).filename
      end

      def initialize(statement)
        @statement = statement
      end

      def filename
        "extracto-#{slug}-#{Date.current.iso8601}.#{extension}"
      end

      private

      attr_reader :statement

      def source
        statement.source
      end

      def movements
        statement.movements
      end

      def extension
        raise NotImplementedError
      end

      def slug
        source.name.to_s.parameterize.presence || "fuente"
      end

      def row(movement, amount: signed_amount(movement).to_s("F"))
        [
          movement.date.iso8601,
          safe_text(movement.description),
          safe_text(movement.secondary),
          safe_text(movement.category&.name),
          safe_text(movement.movement_type),
          amount,
          safe_text(movement.related_source&.name)
        ]
      end

      def signed_amount(movement)
        movement.direction == "in" ? movement.amount.to_d : -movement.amount.to_d
      end

      def safe_text(value)
        text = value.to_s
        return text if text.empty?
        return text unless FORMULA_PREFIXES.any? { |prefix| text.start_with?(prefix) }

        "'#{text}"
      end

      def kind_label
        I18n.t("kinds.#{source.kind}", default: source.kind.to_s.titleize)
      end

      def status_label
        source.active? ? I18n.t("common.active") : I18n.t("common.inactive", default: "Inactiva")
      end

      def current_balance
        return source.outstanding_balance.to_d if source.loan?
        return source.used_credit.to_d if source.debt?

        source.balance.to_d
      end

      def money(value)
        MoneyFormat.currency(value)
      end
    end
  end
end
