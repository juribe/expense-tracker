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

  # The Día de Balance page is taller than the test viewport. Selenium does
  # not always scroll a row action into view before clicking, so center it
  # first to avoid the sticky topbar intercepting the click.
  def scroll_and_click(element)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", element)
    element.click
  end
end
