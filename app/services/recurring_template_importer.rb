# frozen_string_literal: true

require 'csv'

class RecurringTemplateImporter
  attr_reader :user, :templates, :errors, :notice

  def initialize(user:)
    @user = user
    @templates = []
    @errors = []
    @notice = []
  end

  def call(csv_file)
    CSV.foreach(csv_file.path, headers: true) do |row|
      process_row(row)
    end

    user.recurring_templates.insert_all!(templates) unless templates.empty?

    @notice << "#{templates.size} recurring template(s) imported successfully."
    @notice.join(" ")
  rescue => e
    @errors << "Import failed: #{e.message}"
    ""
  end

  private

  def process_row(row)
    category_name = row["category"]&.strip
    return if category_name.blank?

    category = Category.find_or_create_by!(name: category_name)

    template = {
      user_id: user.id,
      category_id: category.id,
      kind: row["kind"]&.strip&.downcase || "expense",
      amount: parse_amount(row["amount"]),
      description: row["description"]&.strip,
      payment_day: parse_payment_day(row["payment_day"]),
      active: row["active"] =~ /^(true|1|yes)$/i ? true : false,
      created_at: Time.current,
      updated_at: Time.current
    }

    @templates << template
  end

  def parse_amount(value)
    return nil if value.blank?

    value.to_s.delete(",").to_d
  end

  def parse_payment_day(value)
    return nil if value.blank?

    day = value.to_i
    return day if (1..31).include?(day)

    nil
  end
end