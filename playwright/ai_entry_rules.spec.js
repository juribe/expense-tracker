const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

// The parser assigns its own category to detected expenses (a guess, not an
// explicit user choice), so at save time a matching transaction rule must
// take precedence. These specs exercise the confirm-and-save flow
// (parse → preview modal → bulk_create) end to end.
test.describe('AI entry – transaction rules take precedence over parser categories', () => {
  const TEXT = 'gaste 50 mil en didi con la tarjeta visa infinite';

  function mockParse(page, expense) {
    page.route(/\/parse/, (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          expenses: [ expense ],
          transcription: TEXT,
          errors: [],
          engine: 'heuristic'
        })
      });
    });
  }

  async function detectAndSave(page) {
    await page.goto('/expenses');
    await page.getByTestId('ai-text-input').fill(TEXT);
    await page.getByTestId('ai-parse-button').click();
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
    await expect(page.getByTestId('ai-row')).toHaveCount(1);

    await page.getByTestId('ai-save-all').click();
    await expect(page).toHaveURL(/\/expenses$/);
  }

  test('uses the rule category when a rule matches the detected expense', async ({ page }) => {
    await signUp(page);
    const ruleCategory = `Apps-${Date.now()}`;
    await createCategory(page, ruleCategory);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('description_contains');
    await page.locator('#transaction_rule_description_contains').fill('didi');
    await page.locator('#transaction_rule_category_id').selectOption({ label: ruleCategory });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    // The parser guesses a new "Didi..." category; the rule must win on save.
    mockParse(page, {
      amount: 50000,
      description: 'Didi Tarjeta Visa Infinite',
      transaction_date: '2026-09-07',
      category_name: 'Didi Tarjeta Visa Infinite',
      create_category: true,
      confidence: 0.9
    });

    await detectAndSave(page);

    const row = page.locator('#expenseTable tr', { hasText: 'Didi Tarjeta Visa Infinite' });
    await expect(row).toBeVisible();
    await expect(row).toContainText(ruleCategory);

    // The parser's suggested category must not linger in the categories list.
    await page.goto('/categories');
    await expect(page.locator('body', { hasText: 'Didi Tarjeta Visa Infinite' })).toHaveCount(0);
  });

  test('keeps the category the user explicitly picked in the confirm card', async ({ page }) => {
    await signUp(page);
    const otherCategory = `Otros-${Date.now()}`;
    await createCategory(page, otherCategory);
    const ruleCategory = `Apps-${Date.now()}`;
    await createCategory(page, ruleCategory);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('description_contains');
    await page.locator('#transaction_rule_description_contains').fill('didi');
    await page.locator('#transaction_rule_category_id').selectOption({ label: ruleCategory });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    mockParse(page, {
      amount: 50000,
      description: 'Didi viaje',
      transaction_date: '2026-09-07',
      category_name: 'Transportation',
      create_category: true,
      confidence: 0.9
    });

    await page.goto('/expenses');
    await page.getByTestId('ai-text-input').fill(TEXT);
    await page.getByTestId('ai-parse-button').click();
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();

    // User explicitly changes the category in the confirm card.
    const row = page.getByTestId('ai-row');
    await row.locator('.ai-field-category').selectOption({ label: otherCategory });
    await page.getByTestId('ai-save-all').click();
    await expect(page).toHaveURL(/\/expenses$/);

    const savedRow = page.locator('#expenseTable tr', { hasText: 'Didi viaje' });
    await expect(savedRow).toBeVisible();
    await expect(savedRow).toContainText(otherCategory);
  });

  test('keeps the parser category when no rule matches', async ({ page }) => {
    await signUp(page);

    mockParse(page, {
      amount: 50000,
      description: 'Didi viaje',
      transaction_date: '2026-09-07',
      category_name: 'Transportation',
      create_category: true,
      confidence: 0.9
    });

    await detectAndSave(page);

    const row = page.locator('#expenseTable tr', { hasText: 'Didi viaje' });
    await expect(row).toBeVisible();
    await expect(row).toContainText('Transportation');
  });
});
