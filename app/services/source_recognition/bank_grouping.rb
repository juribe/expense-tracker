# frozen_string_literal: true

module SourceRecognition
  # BankGrouping
  # Single source of truth for the recognition-page bank grouping: which
  # money sources belong to the same bank group and which member is the
  # SEED (the group's bank-configuration owner). Used by the matcher, the
  # recognition controller, the discovery service and the consolidation task
  # so all of them agree on group membership.
  #
  # Key: the attached polymorphic institution; legacy unattached rows fall
  # back to their folded bank token; rows without any bank are single-source
  # groups.
  module BankGrouping
    BANK_IDENTIFIER_KINDS = %w[sender domain subject header].freeze

    module_function

    def key(source)
      if source.institution_type.present? && source.institution_id.present?
        "#{source.institution_type}:#{source.institution_id}"
      else
        token = TextNormalizer.fold(source.institution_token.to_s)
        token.blank? ? "source:#{source.id}" : "legacy:#{token}"
      end
    end

    # user_sources must already be scoped to ONE user (privacy boundary).
    def groups_for(user_sources)
      user_sources.each_with_object({}) do |source, index|
        index[key(source)] ||= []
        index[key(source)] << source
      end
    end

    def seed_for(groups, source)
      members = groups[key(source)] or return source
      members.min_by { |member| [ member.created_at, member.id ] }
    end
  end
end
