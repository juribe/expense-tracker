const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

// The Expense Playground processes inputs into an ExpenseCandidate without
// creating a real expense; only the explicit "Create Expense" action writes
// one. The process endpoint is mocked (same approach as the AI entry specs:
// the sandbox server has a real MISTRAL_API_KEY, so we never hit it); the
// create flow runs for real.
test.describe('expense playground', () => {
  const CANDIDATE = {
    amount: 50000,
    currency: 'COP',
    category_id: null,
    category_name: 'Restaurants',
    description: 'Almuerzos',
    merchant: null,
    date: '2026-09-09',
    source: 'playground',
    confidence: 0.94
  };

  const STEPS = {
    input: { type: 'text', text: 'Me gasté 50mil en almuerzos', image: null },
    ocr: { applicable: false },
    extraction: {
      engine: 'heuristic',
      raw: [ { amount: 50000, description: 'Almuerzos', transaction_date: '2026-09-09', category_name: 'Restaurants', confidence: 0.94, warnings: [] } ],
      detected_count: 1
    },
    normalization: { amount: 50000, currency: 'COP', category_id: null, category_name: 'Restaurants', date: '2026-09-09', warnings: [] },
    validation: {
      valid: true,
      checks: [
        { label: 'Amount present', passed: true },
        { label: 'Currency detected', passed: true },
        { label: 'Category mapped', passed: true },
        { label: 'Valid date', passed: true }
      ],
      errors: []
    }
  };

  function mockProcess(page, payload, status = 200) {
    page.route(/\/expense-playground\/process/, (route) => {
      route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(payload) });
    });
  }

  function okPayload(overrides = {}) {
    return Object.assign({
      ok: true,
      run_id: 42,
      engine: 'heuristic',
      duration_ms: 123,
      candidate: CANDIDATE,
      errors: [],
      warnings: [],
      steps: STEPS,
      evaluation: null
    }, overrides);
  }

  test('tabs switch between text and image inputs', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');

    await expect(page.getByTestId('panel-text')).toBeVisible();
    await expect(page.getByTestId('panel-image')).toBeHidden();

    await page.getByTestId('tab-image').click();
    await expect(page.getByTestId('panel-text')).toBeHidden();
    await expect(page.getByTestId('panel-image')).toBeVisible();

    await page.getByTestId('tab-text-image').click();
    await expect(page.getByTestId('panel-text')).toBeVisible();
    await expect(page.getByTestId('panel-image')).toBeVisible();
    await expect(page.getByTestId('text-image-hint')).toBeVisible();
  });

  test('clicking an example fills the textarea', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');

    await page.getByTestId('playground-examples').getByRole('button').first().click();
    await expect(page.getByTestId('playground-text-input')).toHaveValue('Me gasté 50mil en almuerzos');
  });

  test('processing shows the candidate, pipeline details and history entry without creating an expense', async ({ page }) => {
    await signUp(page);
    mockProcess(page, okPayload());
    await page.goto('/expense-playground');

    await page.getByTestId('playground-text-input').fill('Me gasté 50mil en almuerzos');
    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-result')).toBeVisible();
    await expect(page.getByTestId('detected-amount')).toContainText('$50,000');
    await expect(page.getByTestId('detected-category')).toContainText('Restaurants');
    await expect(page.getByTestId('detected-confidence')).toContainText('94%');

    await expect(page.getByTestId('playground-steps')).toContainText('Me gasté 50mil en almuerzos');
    await expect(page.getByTestId('playground-steps')).toContainText('50000');
    await expect(page.getByTestId('playground-steps')).toContainText('heuristic');

    await expect(page.getByTestId('playground-history-row').first()).toBeVisible();

    // Nothing was created yet
    await page.goto('/expenses');
    await expect(page.locator('body')).not.toContainText('Almuerzos');
  });

  test('expected results are evaluated against the detection', async ({ page }) => {
    await signUp(page);
    mockProcess(page, okPayload({
      evaluation: {
        checks: [
          { field: 'amount', expected: '50000', actual: '50000', passed: true },
          { field: 'category', expected: 'food', actual: 'Restaurants', passed: false }
        ],
        passed: 1,
        total: 2,
        ok: false
      }
    }));
    await page.goto('/expense-playground');

    await page.getByTestId('playground-expected-toggle').click();
    await page.getByTestId('expected-amount').fill('50000');
    await page.getByTestId('expected-category').fill('food');

    await page.getByTestId('playground-text-input').fill('Me gasté 50mil en almuerzos');
    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-evaluation')).toBeVisible();
    await expect(page.getByTestId('evaluation-score')).toContainText('1 / 2');
    await expect(page.getByTestId('evaluation-check')).toHaveCount(2);
    const failedCheck = page.getByTestId('evaluation-check').filter({ hasText: 'category' });
    await expect(failedCheck).toContainText('✗');
  });

  test('user can edit the candidate and create the expense', async ({ page }) => {
    await signUp(page);
    mockProcess(page, okPayload());
    await page.goto('/expense-playground');

    await page.getByTestId('playground-text-input').fill('Me gasté 50mil en almuerzos');
    await page.getByTestId('playground-process-button').click();
    await expect(page.getByTestId('playground-result')).toBeVisible();

    // Edit before creating
    await page.getByTestId('edit-amount').fill('51000');
    await page.getByTestId('edit-description').fill('Almuerzo del equipo');
    await page.getByTestId('playground-create-button').click();

    await expect(page.getByTestId('playground-success')).toBeVisible();
    await expect(page.getByTestId('playground-success')).toContainText('Gasto creado');

    await page.goto('/expenses');
    const row = page.locator('#expenseTable tr', { hasText: 'Almuerzo del equipo' });
    await expect(row).toBeVisible();
    await expect(row).toContainText('51.000');
  });

  test('processing failures surface a clear error', async ({ page }) => {
    await signUp(page);
    mockProcess(page, {
      ok: false,
      run_id: 43,
      engine: 'vision',
      duration_ms: 45,
      candidate: null,
      errors: ['Could not extract an expense from this input. Reason: no expense could be detected in the image.'],
      warnings: [],
      steps: STEPS,
      evaluation: null
    }, 422);
    await page.goto('/expense-playground');

    await page.getByTestId('playground-text-input').fill('nada que ver');
    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-result-errors')).toBeVisible();
    await expect(page.getByTestId('playground-result-errors')).toContainText('Could not extract an expense');
    // No candidate was rendered
    await expect(page.getByTestId('detected-amount')).toHaveText('');
    await expect(page.getByTestId('edit-amount')).toHaveValue('');
  });
});
