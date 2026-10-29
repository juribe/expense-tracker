# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium_chrome_headless

  private

  # Bootstrap ignores Modal#hide while the opening fade is still running.
  # Tests that close a modal right after opening it must wait for the
  # transition to finish, otherwise the close click is silently dropped.
  def wait_for_modal_transition(selector)
    page.document.synchronize do
      ready = page.evaluate_script(<<~JS)
        (() => {
          const el = document.querySelector(#{selector.to_json});
          if (!el || !window.bootstrap) return false;
          const instance = bootstrap.Modal.getInstance(el);
          return !!instance && instance._isShown === true && instance._isTransitioning === false;
        })()
      JS
      raise Capybara::ElementNotFound, "modal #{selector} is not fully shown" unless ready
    end
  end
end
