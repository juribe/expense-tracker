# frozen_string_literal: true

module SourceRecognition
  # Catalog
  # Read access to the seeded financial email catalog (Colombian institutions,
  # global financial keywords, subject patterns). Callers load the lists once
  # per run and pass them around; matching itself is cheap, deterministic and
  # accent-insensitive.
  module Catalog
    module_function

    def institutions = FinancialInstitution.active.order(:id).to_a

    def keywords = FinancialKeyword.order(:id).to_a

    def subject_patterns = FinancialSubjectPattern.order(:id).to_a

    # Domain index: verified official domain → institution. Subdomains of a
    # listed domain count (mail.davibank.com → davibank.com).
    def domains_index(institutions = self.institutions)
      institutions.each_with_object({}) do |institution, index|
        institution.folded_domains.each do |domain|
          index[domain] ||= institution
        end
      end
    end

    def match_domain(domain, index = domains_index)
      return nil if domain.blank?

      normalized = fold(domain)
      index.each do |known, institution|
        return institution if normalized == known || normalized.end_with?(".#{known}")
      end
      nil
    end

    # Institutions whose alias appears in the text (word-boundary, folded).
    def match_text(text, institutions = self.institutions)
      folded = fold(text)
      institutions.select do |institution|
        institution.folded_aliases.any? { |alias_word| contains_word?(folded, alias_word) }
      end
    end

    # The alias of `institution` present in the text, longest first
    # ("banco davibank" wins over "davibank"). Returns nil when none matches.
    def matched_alias(text, institution)
      folded = fold(text)
      institution.folded_aliases
                 .select { |alias_word| contains_word?(folded, alias_word) }
                 .max_by(&:length)
    end

    def contains_word?(folded_text, value)
      TextNormalizer.contains_word?(folded_text, value)
    end

    def fold(text)
      TextNormalizer.fold(text)
    end
  end
end
