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

test.describe("AI powered expense entry survives Turbo navigation", () => {
  test("detect-expenses button still works after navigating away and back", async ({ page }) => {
    await signUp(page);
    await mockParseEndpoint(page);
    await page.goto('/expenses');
    await expect(page.getByTestId('ai-text-input')).toBeVisible();

    // Turbo Drive visit away from /expenses...
    await page.getByRole('link', { name: 'Panel' }).click();
    await expect(page).toHaveURL(/dashboard/);

    // ...and back through the navbar link (client-side Turbo visit, no reload).
    await page.getByRole('link', { name: 'Gastos', exact: true }).click();
    await expect(page).toHaveURL(/\/expenses/);

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
    await page.getByTestId('ai-mic-button').click();
    await expect(page.getByTestId('ai-text-input')).toHaveValue('50 mil en almuerzo');
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
  });
});
