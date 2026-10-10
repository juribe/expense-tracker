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

    # True when the message's SENDER is owned by the bank: either its
    # address domain equals an institution's official domain (or a
    # subdomain) or the From string itself names the bank (alias in the
    # display name / local part — payment relays like
    # "Banco DaviBank via claro.com.co").
    #
    # Payment processors and telecom receipts (epayco, claro, PSE) may
    # mention the bank in the body — they are not the bank and must never
    # contribute bank-identity values (senders, domains, subject patterns).
    def bank_owned_sender?(message, institution, index = domains_index)
      return false unless institution

      from = message[:from].to_s
      email = from[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]
      return false unless email

      match_domain(email.split("@").last, index) == institution ||
        institution.folded_aliases.any? { |alias_word| contains_word?(from, alias_word) }
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
