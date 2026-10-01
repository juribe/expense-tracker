# frozen_string_literal: true

require "test_helper"

module FinancialChats
  class MessagesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = User.create!(
        name: "Test User",
        email: "chat_messages_test@example.com",
        password: "password123"
      )
    end

    test "POST creates the user's chat and persists the user message" do
      sign_in @user
      assert_equal 0, FinancialChat.count

      post financial_chat_messages_path, params: { content: "How much did I spend this month?" }, as: :json

      assert_response :created
      chat = FinancialChat.find_by!(user: @user)
      message = chat.messages.sole
      assert_equal "user", message.role
      assert_equal "How much did I spend this month?", message.content
      assert_equal "sent", message.status
    end

    test "POST enqueues FinancialChatJob for the chat and message" do
      sign_in @user

      with_active_job_adapter(:test) do
        post financial_chat_messages_path, params: { content: "What about restaurants?" }, as: :json
        job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j| j[:job] == FinancialChatJob }

        chat = FinancialChat.find_by!(user: @user)
        message = chat.messages.sole
        assert_not_nil job
        assert_equal "ai", job[:queue]
        assert_equal [ chat.id, message.id ], job["arguments"]
      end
    end

    test "POST response carries the persisted message payload" do
      sign_in @user
      post financial_chat_messages_path, params: { content: "Hi" }, as: :json

      body = JSON.parse(response.body)
      assert_equal "user", body.dig("message", "role")
      assert_equal "Hi", body.dig("message", "content")
      assert_equal "sent", body.dig("message", "status")
    end

    test "POST rejects blank content" do
      sign_in @user
      post financial_chat_messages_path, params: { content: "   " }, as: :json

      assert_response :unprocessable_entity
      assert_equal 0, FinancialChatMessage.count
    end

    test "POST requires authentication" do
      post financial_chat_messages_path, params: { content: "Hi" }, as: :json
      assert_response :unauthorized
      assert_equal 0, FinancialChatMessage.count
    end
  end
end
