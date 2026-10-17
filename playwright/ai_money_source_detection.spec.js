const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

async function openExpenses(page) {
  await page.goto('/expenses');
  await expect(page.getByTestId('ai-form')).toHaveAttribute('data-ai-initialized', 'true');
}

async function createMoneySource(page, name, kind = 'wallet') {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption(kind);
  await page.locator('#money_source_active').check();
  await page.locator('form input[type="submit"]').click();
  await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

  const href = await page.locator('a[href^="/money_sources/"]', { hasText: name }).first().getAttribute('href');
  return href.split('/').filter(Boolean).pop();
}

// The parse endpoint asks the AI provider to split the text into expenses; CI
// runs without an AI key, so these cases stub the response to exercise how the
// form pre-selects the money source the server detected. Source detection
// itself is covered by the MoneySources::Detector unit tests.
async function mockParse(page, expenses) {
  await page.route('**/expenses/parse.json', (route) => route.fulfill({
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ transcription: '', expenses, errors: [] }),
  }));
}

function detectedExpense(overrides = {}) {
  return {
    amount: 50000,
    description: 'Almuerzo',
    transaction_date: null,
    category_id: null,
    category_name: null,
    create_category: false,
    confidence: 0.95,
    low_confidence: false,
    warnings: [],
    money_source_id: null,
    money_source_name: null,
    status: 'ok',
    category_suggestion: null,
    ...overrides,
  };
}

test.describe('AI expense detection selects the money source', () => {
  test('pre-selects the source mentioned by name in the detected expense row', async ({ page }) => {
    await signUp(page);
    const nequiId = await createMoneySource(page, 'Nequi', 'wallet');
    await mockParse(page, [detectedExpense({ money_source_id: nequiId, money_source_name: 'Nequi' })]);

    await openExpenses(page);
    await page.getByTestId('ai-text-input').fill('Gasté 50 mil en almuerzo desde nequi');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-parse-button')).toBeEnabled({ timeout: 30000 });
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible({ timeout: 30000 });
    await expect(page.getByTestId('ai-row')).toHaveCount(1);

    const sourceSelect = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelect.locator('option:checked')).toHaveText('Nequi');
  });

  test('pre-selects the source matched by a keyword in the detected expense row', async ({ page }) => {
    await signUp(page);
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill('Visa');
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    await page.goto('/money_sources/recognition');
    const groupToggle = page.locator('[data-testid="recognition-bank-group"]', { hasText: 'Visa' })
      .locator('[data-testid="recognition-bank-toggle"]').first();
    if ((await groupToggle.getAttribute('aria-expanded')) === 'false') await groupToggle.click();
    const row = page.locator('[data-testid="recognition-row"]', { hasText: 'Visa' });
    await row.locator('[data-testid="edit-recognition"]').click();
    await expect(page.getByTestId('recognition-edit-panel')).toBeVisible();
    await page.locator('[data-recognition-chips="keywords"] [data-recognition-add]').click();
    const keywordInput = page.locator('[data-recognition-inline-add="keywords"]');
    await keywordInput.fill('tarjeta clásica');
    await keywordInput.press('Enter');
    await page.getByTestId('recognition-save').click();
    await expect(page.getByText('Configuración de reconocimiento guardada.')).toBeVisible();

    await openExpenses(page);
    await page.getByTestId('ai-text-input').fill('Pag 50 mil en el restaurante con la tarjeta clásica');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-parse-button')).toBeEnabled({ timeout: 30000 });
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible({ timeout: 30000 });
    await expect(page.getByTestId('ai-row')).toHaveCount(1);

    const sourceSelect = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelect.locator('option:checked')).toHaveText('Visa');
  });

  test('leaves the source unselected when no source is mentioned in the text', async ({ page }) => {
    await signUp(page);
    await createMoneySource(page, 'Nequi', 'wallet');
    await mockParse(page, [detectedExpense()]);

    await openExpenses(page);
    await page.getByTestId('ai-text-input').fill('Gasté 50 mil en almuerzo');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-parse-button')).toBeEnabled({ timeout: 30000 });
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible({ timeout: 30000 });
    await expect(page.getByTestId('ai-row')).toHaveCount(1);

    const sourceSelect = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelect.locator('option:checked')).toHaveText('Ninguno');
  });

  test('applies the mentioned source to every detected expense row', async ({ page }) => {
    await signUp(page);
    await createMoneySource(page, 'Nequi', 'wallet');

    await openExpenses(page);
    await page.getByTestId('ai-text-input').fill('Gasté 50 mil en restaurante y 20 mil en parqueadero desde nequi');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-parse-button')).toBeEnabled({ timeout: 30000 });
    await expect(page.getByTestId('ai-preview-modal')).toBeVisible({ timeout: 30000 });
    await expect(page.getByTestId('ai-row')).toHaveCount(2);

    const sourceSelects = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelects).toHaveCount(2);
    for (let i = 0; i < 2; i++) {
      await expect(sourceSelects.nth(i).locator('option:checked')).toHaveText('Nequi');
    }
  });
});
