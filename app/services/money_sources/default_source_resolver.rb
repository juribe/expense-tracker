# frozen_string_literal: true

module MoneySources
  # Resolves the source a new movement must use, according to the user's
  # tracking mode. This is the single entry point every creation channel uses:
  # manual forms, WhatsApp, Gmail, AI, imports, MCP and recurring templates.
  #
  # Simple mode always uses General. Advanced mode uses the explicit source
  # when it belongs to the user, otherwise the configured default source.
  #
  #   MoneySources::DefaultSourceResolver.new(user: user, explicit: source).resolve
  class DefaultSourceResolver
    def initialize(user:, explicit: nil)
      @user = user
      @explicit = explicit
    end

    def resolve
      return if @user.nil?
      return @user.general_money_source if @user.money_tracking_simple?
      return explicit_source if explicit_source.present?
      return nil if explicit_given?

      default_source
    end

    def resolve!
      resolve || raise(MissingSource, "a money source is required")
    end

    class MissingSource < StandardError; end

    private

    def explicit_given?
      @explicit.present?
    end

    def explicit_source
      @explicit_source ||= begin
        case @explicit
        when MoneySource
          @explicit if @explicit.user_id == @user.id
        when String
          normalized = UuidParams.normalize(@explicit)
          @user.money_sources.find_by(id: normalized) if normalized
        end
      end
    end

    def default_source
      source = @user.default_money_source
      source if source.present? && source.user_id == @user.id && source.active?
    end
  end
end
