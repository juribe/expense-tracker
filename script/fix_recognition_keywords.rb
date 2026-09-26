# One-off data fix: re-attaches recognition keywords to their rightful money
# sources for a user whose Gmail-derived identifiers landed on the wrong
# sources. Dry-run by default; apply with APPLY=1:
#
#   bin/rails runner script/fix_recognition_keywords.rb            # dry-run
#   APPLY=1 bin/rails runner script/fix_recognition_keywords.rb    # apply
#
# Idempotent: re-running detects nothing left to move.
require "json"

USER_ID = 6

# value => target source name (exact match for the user's sources).
MOVES = {
  "lifemiles" => "Tarjeta Lifemiles",
  "lifemile" => "Tarjeta Lifemiles",
  "5194" => "Tarjeta Lifemiles",
  "davibank" => "Cuenta Davibank",
  "efectivo" => "efectivo",
  "dinero" => "efectivo",
  "plata" => "efectivo",
  "tarjeta" => "Tarjeta Visa Infinite"
}.freeze

# Keywords to add to a source (created as confirmed, origin user).
ADDITIONS = {
  "Cuenta Davibank" => %w[ahorros ahorro]
}.freeze

user = User.find(USER_ID)
sources = user.money_sources.active.includes(recognition: :recognition_identifiers).index_by(&:name)

recognitions = sources.values.index_by { |source| source.recognition&.id }
keyword_rows = MoneySourceRecognitionIdentifier
  .where(money_source_recognition_id: recognitions.keys.compact)
  .where(kind: "keyword", status: "confirmed")

def source_name_for(recognitions, row)
  recognitions[row.money_source_recognition_id]&.name
end

def ensure_recognition_for(sources, target_name)
  source = sources[target_name]
  raise "source #{target_name.inspect} not found" if source.nil?

  source.ensure_recognition
end

puts "Current confirmed keywords per source:"
sources.each_value do |source|
  keywords = source.recognition&.recognition_identifiers
    &.select { |row| row.keyword? && row.confirmed? }
    &.map(&:value) || []
  puts "  #{source.name}: #{keywords.inspect}"
end
puts

changes = []
MOVES.each do |value, target_name|
  target_recognition = ensure_recognition_for(sources, target_name)
  keyword_rows.where(value: value).find_each do |row|
    next if row.money_source_recognition_id == target_recognition.id

    if MoneySourceRecognitionIdentifier.exists?(
      money_source_recognition_id: target_recognition.id, kind: "keyword", value: value
    )
      # The target already carries the value: the stray row is a duplicate.
      changes << { row_id: row.id, value: value, action: "delete duplicate",
                   from: source_name_for(recognitions, row) || "(unknown)", to: target_name }
    else
      changes << { row_id: row.id, value: value, action: "move",
                   from: source_name_for(recognitions, row) || "(unknown)", to: target_name }
    end
  end
end

additions = []
ADDITIONS.each do |target_name, values|
  target_recognition = ensure_recognition_for(sources, target_name)
  values.each do |value|
    next if MoneySourceRecognitionIdentifier.exists?(
      money_source_recognition_id: target_recognition.id, kind: "keyword", value: value
    )

    additions << { value: value, to: target_name }
  end
end

if changes.empty? && additions.empty?
  puts "Nothing to do — recognition data is already correct."
  exit
end

puts "Planned changes:"
changes.each { |change| puts "  #{change[:value].inspect} (identifier ##{change[:row_id]}): #{change[:action]} — #{change[:from]} -> #{change[:to]}" }
puts "Planned additions:"
additions.each { |addition| puts "  #{addition[:value].inspect} -> #{addition[:to]}" }

if ENV["APPLY"].present?
  ActiveRecord::Base.transaction do
    changes.each do |change|
      row = MoneySourceRecognitionIdentifier.find(change[:row_id])
      if change[:action] == "delete duplicate"
        row.destroy!
      else
        target_recognition = ensure_recognition_for(sources, change[:to])
        row.update!(money_source_recognition_id: target_recognition.id)
      end
    end
    additions.each do |addition|
      target_recognition = ensure_recognition_for(sources, addition[:to])
      MoneySourceRecognitionIdentifier.create!(
        money_source_recognition_id: target_recognition.id,
        kind: "keyword",
        value: addition[:value],
        status: "confirmed",
        origin: "user"
      )
    end
  end
  puts "APPLIED."
else
  puts "Dry run — re-run with APPLY=1 to apply."
end

puts
puts "Resulting keywords per source:"
sources.each_value do |source|
  source.recognition&.reload
  keywords = source.recognition&.recognition_identifiers
    &.select { |row| row.keyword? && row.confirmed? }
    &.map(&:value) || []
  puts "  #{source.name}: #{keywords.inspect}"
end
