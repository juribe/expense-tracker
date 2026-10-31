# frozen_string_literal: true

module Mcp
  # Mcp::SettingsController
  # RESTful token management for external MCP clients. Tokens are shown once
  # and can be revoked; they never reuse the web session as a credential.
  class SettingsController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    def show
      load_tokens
    end

    def create
      name = token_params[:name].to_s.strip
      if name.blank?
        load_tokens
        flash.now[:alert] = t("mcp.settings.name_required")
        return render :show, status: :unprocessable_entity
      end

      @token, @plain_token = McpAccessToken.issue!(user: current_user, name: name, scopes: scopes_param)
      load_tokens
      render :show
    end

    def destroy
      token = current_user.mcp_access_tokens.find(params[:id])
      token.revoke!
      redirect_to mcp_settings_path, notice: t("mcp.settings.revoked")
    end

    private

    def load_tokens
      @tokens = current_user.mcp_access_tokens.order(created_at: :desc)
    end

    def token_params
      params.expect(mcp_token: [ :name, :write_access ])
    end

    def scopes_param
      scopes = [ "read" ]
      scopes << "write" if token_params[:write_access].to_s == "1"
      scopes
    end

    def not_found
      head :not_found
    end
  end
end
