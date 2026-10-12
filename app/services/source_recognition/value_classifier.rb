# frozen_string_literal: true

module SourceRecognition
  # ValueClassifier
  # Shared classification of free-text recognition values by section. The
  # senders section mixes real addresses (sender) and bare domains (domain):
  # a value with a top-level "." and no "@" is a domain. The subjects section
  # mixes subject text (subject) and RFC header patterns ("From: ..."):
  # a value with a top-level ":" is a header.
  module ValueClassifier
    module_function

    SECTIONS = {
      "keywords" => %i[keyword],
      "senders"  => %w[sender domain],
      "subjects" => %w[subject header]
    }.freeze

    def senders(list)
      senders_list, domains = [], []
      list.compact_blank.each do |value|
        if domain?(value)
          domains << value
        else
          senders_list << value
        end
      end
      [ senders_list, domains ]
    end

    def subjects(list)
      subjects_list, headers = [], []
      list.compact_blank.each do |value|
        if value.include?(":")
          headers << value
        else
          subjects_list << value
        end
      end
      [ subjects_list, headers ]
    end

    # The kind a single value should be stored as within a section.
    def kind_of(section, value)
      case section
      when "keywords" then "keyword"
      when "senders" then domain?(value) ? "domain" : "sender"
      when "subjects" then value.include?(":") ? "header" : "subject"
      else "keyword"
      end
    end

    def domain?(value)
      value.match?(/\A[\w.-]+\.[a-z]{2,}\z/i) && !value.include?("@")
    end
  end
end
