# frozen_string_literal: true

module Gmf
  # Gmf::OperationClassification
  # Classifies an operation for GMF purposes, independently of the
  # mathematical calculation.
  #
  # Values:
  #   :taxable_consumes_exemption  - gravada y consume la exención
  #   :taxable_no_exemption        - gravada y NO consume la exención
  #   :legally_exempt             - exenta por disposición legal
  #   :non_taxable_event          - no constituye hecho generador
  #
  # Example: Gmf::OperationClassification.classify(operation_type: :credit_card_purchase)
  module OperationClassification
    TAXABLE_CONSUMES = :taxable_consumes_exemption
    TAXABLE_NO_CONSUME = :taxable_no_exemption
    LEGALLY_EXEMPT = :legally_exempt
    NON_TAXABLE = :non_taxable_event

    CONSUMES_EXEMPTION = [TAXABLE_CONSUMES].freeze

    def self.classify(operation_type:, money_source: nil, metadata: {})
      case operation_type.to_sym
      when :expense_payment, :debit_card_purchase, :withdrawal, :service_payment,
           :credit_card_payment
        TAXABLE_CONSUMES
      when :transfer
        # Transfers between the user's own accounts consume the exemption by
        # default (gravadas), but are flagged as uncertain for reconciliation.
        TAXABLE_CONSUMES
      when :credit_card_purchase
        NON_TAXABLE
      when :income, :balance_adjustment
        NON_TAXABLE
      else
        NON_TAXABLE
      end
    end

    def self.consumes_exemption?(classification)
      CONSUMES_EXEMPTION.include?(classification)
    end

    def self.taxable?(classification)
      classification == TAXABLE_CONSUMES || classification == TAXABLE_NO_CONSUME
    end
  end
end
