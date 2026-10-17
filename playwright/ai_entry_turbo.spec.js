const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

const PARSE_RESPONSE = {
  expenses: [
    {
      amount: 50000,
      description: "Restaurante",
      transaction_date: "2026-08-22",
      category_name: "Restaurants",
      confidence: 0.95,
      create_category: false
    }
  ],
  transcription: "50 mil en almuerzo",
  errors: [],
  engine: "heuristic"
};

async function mockParseEndpoint(page) {
  await page.route(/\/parse/, (route) => {
    route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(PARSE_RESPONSE)
    });
  });
}

// The sidebar is not visible at the test viewport, so trigger a client-side
// Turbo Drive visit programmatically (no full reload) and wait for a unique
// element of the destination instead of the URL alone (Turbo updates the URL
// before the new page renders).
async function visitViaTurbo(page, href, targetLocator) {
  await page.evaluate((h) => {
    document.querySelector(`a.sidebar-link[href="${h}"]`).click();
  }, href);
  await expect(targetLocator).toBeVisible();
}

test.describe("AI powered expense entry survives Turbo navigation", () => {
  test("detect-expenses button still works after navigating away and back", async ({ page }) => {
    await signUp(page);
    await mockParseEndpoint(page);
    await page.goto('/expenses');
    await expect(page.getByTestId('ai-text-input')).toBeVisible();

    // Turbo Drive visit away from /expenses...
    await visitViaTurbo(page, '/dashboard', page.getByText('Dinero en cuentas').first());

    // ...and back through a client-side Turbo visit (no reload).
    await visitViaTurbo(page, '/expenses', page.getByTestId('ai-entry-card'));
    // Wait for the freshly rendered form to be re-initialized (the script marks
    // it via dataset) so the click below cannot race the Turbo re-render.
    await expect(page.getByTestId('ai-form')).toHaveAttribute('data-ai-initialized', 'true');

    // Regression: the inline script used to bail out on a one-shot window
    // flag, leaving these buttons dead after any Turbo navigation.
    await page.getByTestId('ai-text-input').fill('50 mil en almuerzo');
    await page.getByTestId('ai-parse-button').click();
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
    await expect(page.getByTestId('ai-row')).toHaveCount(1);
  });

  test("dictate fills the textarea using SpeechRecognition", async ({ page }) => {
    await signUp(page);
    await mockParseEndpoint(page);

    // Headless browsers have no microphone; emulate the Web Speech API so the
    // widget's dictate flow can be exercised end to end.
    await page.addInitScript(() => {
      class FakeRecognition {
        start() {
          setTimeout(() => {
            if (this.onstart) this.onstart();
            if (this.onresult) {
              this.onresult({
                resultIndex: 0,
                results: [
                  { 0: { transcript: '50 mil en almuerzo' }, length: 1, isFinal: true }
                ]
              });
            }
            if (this.onend) this.onend();
          }, 50);
        }

        stop() {}
      }
      window.SpeechRecognition = FakeRecognition;
      window.webkitSpeechRecognition = FakeRecognition;
    });

    await page.goto('/expenses');
    await expect(page.getByTestId('ai-form')).toHaveAttribute('data-ai-initialized', 'true');
    await page.getByTestId('ai-mic-button').click();
    await expect(page.getByTestId('ai-text-input')).toHaveValue('50 mil en almuerzo');
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
    await expect(page.getByTestId('ai-row')).toHaveCount(1);
  });
});
