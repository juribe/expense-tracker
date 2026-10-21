# frozen_string_literal: true

require "csv"

# Imports recurring templates from a CSV file in two phases:
#
#   RecurringTemplateImporter.new(user:).preview(csv_file)
#     -> array of plain draft rows ("ok"/"error" status, JSON-safe)
#
#   RecurringTemplateImporter.new(user:).import(draft_rows, category_ids:, default_category_id:)
#     -> inserts the resolved rows; skipped rows are collected in #row_errors
#
# Categories must already exist for the user (own or default, matching the row
# kind): the importer never creates categories. The user can fix a category
# row in the preview by selecting an existing category id. Everything runs
# inside a single transaction, so an unexpected failure rolls back completely.
class RecurringTemplateImporter
  HEADER_ALIASES = {
    "category" => "category",
    "categoria" => "category",
    "kind" => "kind",
    "tipo" => "kind",
    "amount" => "amount",
    "monto" => "amount",
    "description" => "description",
    "descripcion" => "description",
    "payment day" => "payment_day",
    "dia de pago" => "payment_day",
    "dia pago" => "payment_day",
    "active" => "active",
    "activo" => "active"
  }.freeze

  KIND_ALIASES = {
    "income" => "income",
    "ingreso" => "income",
    "expense" => "expense",
    "gasto" => "expense"
  }.freeze

  KINDS = KIND_ALIASES.values.freeze
  TRUE_ACTIVE_VALUES = %w[true 1 yes si verdadero activo].freeze

  # Numeric amount shared by validation (service + views) and import.
  # Strings without any digit are considered unparseable, never silently 0.
  def self.normalize_amount(value)
    return nil if value.blank?

    cleaned = value.to_s.delete(",")
    return nil unless cleaned.match?(/\d/)

    cleaned.to_d
  end

  attr_reader :user, :templates, :row_errors, :errors, :notice

  def initialize(user:)
    @user = user
    @templates = []
    @row_errors = []
    @errors = []
    @categories_by_kind = {}
  end

  # Parses and validates every CSV row without touching the templates table.
  # Returns an array of plain hashes, renderable and persistable for the
  # preview screen:
  #   { "id" => "r3", "row_number" => 3, "kind" => "expense", "amount" => "50000",
  #     "description" => ..., "payment_day" => ..., "active" => ...,
  #     "category_id" => ..., "status" => "ok"|"error", "error" => message }
  def preview(csv_file)
    rows = []
    row_number = 1 # header

    CSV.foreach(csv_file.path, headers: true, header_converters: ->(header) { normalize_header(header) }) do |row|
      row_number += 1
      rows << draft_row(row, row_number)
    end

    rows
  rescue => e
    @errors << I18n.t("recurring.import_failed", message: e.message)
    []
  end

  # Re-validates the draft (categories may have changed and the user may have
  # fixed rows in the preview) and inserts the resolved rows. Rows that stay
  # invalid are skipped and reported in #row_errors with their file row number.
  def import(rows, category_ids: {}, default_category_id: nil)
    ActiveRecord::Base.transaction do
      rows.each do |row|
        template = build_template(row, category_ids: category_ids, default_category_id: default_category_id)
        @templates << template if template
      end

      user.recurring_templates.insert_all!(@templates) unless @templates.empty?
    end

    @row_errors << I18n.t("imports.no_rows") if @templates.empty? && @row_errors.empty?
    @notice = I18n.t("recurring.imported", count: @templates.size)
    @notice
  rescue => e
    @errors << I18n.t("recurring.import_failed", message: e.message)
    ""
  end

  private

  def draft_row(row, row_number)
    kind = parse_kind(row["kind"])
    amount = parse_amount(row["amount"])
    category_id = resolve_preview_category(row["category"], kind)
    valid = KINDS.include?(kind) && amount && category_id

    {
      "id" => "r#{row_number}",
      "row_number" => row_number,
      "kind" => kind,
      "kind_valid" => KINDS.include?(kind),
      "amount" => row["amount"].to_s,
      "amount_valid" => amount.present?,
      "description" => row["description"]&.strip,
      "payment_day" => parse_payment_day(row["payment_day"])&.to_s,
      "active" => row["active"].to_s.strip,
      "category_name" => row["category"]&.strip,
      "category_id" => category_id,
      "status" => valid ? "ok" : "error",
      "error" => valid ? nil : error_message_for(kind, amount, row)
    }
  end

  def error_message_for(kind, amount, row)
    return I18n.t("imports.invalid_kind") unless KINDS.include?(kind)
    return I18n.t("imports.missing_amount") if amount.nil?

    category_name = row["category"]&.strip
    if category_name.blank?
      I18n.t("imports.category_required")
    else
      I18n.t("imports.missing_category", name: category_name)
    end
  end

  def build_template(row, category_ids:, default_category_id:)
    row_number = row["row_number"]

    kind = row["kind"]
    return skip_row(row_number, I18n.t("imports.invalid_kind")) unless KINDS.include?(kind)

    amount = parse_amount(row["amount"])
    return skip_row(row_number, I18n.t("imports.missing_amount")) if amount.nil?

    category_id = resolve_import_category(row, category_ids, default_category_id)
    return skip_row(row_number, category_error_for(row["category_name"])) if category_id.nil?

    {
      user_id: user.id,
      category_id: category_id,
      kind: kind,
      amount: amount,
      description: row["description"],
      payment_day: row["payment_day"].presence&.to_i,
      active: parse_active(row["active"]),
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  # The user's preview selection wins over the category resolved at upload
  # time. A category is only usable when it belongs to the user (or is a
  # default) and matches the row kind. When nothing resolves and the upload
  # chose a default category, that category applies if the kind matches.
  def resolve_import_category(row, category_ids, default_category_id)
    [category_ids[row["id"]], row["category_id"], default_category_id].compact_blank.each do |candidate|
      category = Category.for_user(user).find_by(id: candidate)
      return category.id if category && category.category_type == row["kind"]
    end

    nil
  end

  def resolve_preview_category(value, kind)
    return nil unless KINDS.include?(kind)

    category_for(value, kind)&.id
  end

  def skip_row(row_number, message)
    @row_errors << I18n.t("imports.row_error", row: row_number, message: message)
    nil
  end

  def category_error_for(value)
    if value.to_s.strip.blank?
      I18n.t("imports.category_required")
    else
      I18n.t("imports.missing_category", name: value)
    end
  end

  def category_for(value, kind)
    category_name = value&.strip
    return nil if category_name.blank?

    categories_for(kind)[category_name]
  end

  def categories_for(kind)
    @categories_by_kind[kind] ||= Category.for_user(user)
                                          .where(category_type: kind)
                                          .index_by(&:name)
  end

  def normalize_header(header)
    key = I18n.transliterate(header.to_s.delete_prefix("\uFEFF").strip.downcase)
              .gsub(/[\s_]+/, " ")

    HEADER_ALIASES.fetch(key, key)
  end

  def parse_kind(value)
    normalized = I18n.transliterate(value.to_s.strip.downcase)
    return "expense" if normalized.blank?

    KIND_ALIASES.fetch(normalized, normalized)
  end

  def parse_active(value)
    TRUE_ACTIVE_VALUES.include?(I18n.transliterate(value.to_s.strip.downcase))
  end

  def parse_amount(value)
    self.class.normalize_amount(value)
  end

  def parse_payment_day(value)
    return nil if value.blank?

    day = value.to_i
    return day if (1..31).include?(day)

    nil
  end
end
