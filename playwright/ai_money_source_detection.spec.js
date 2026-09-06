const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

async function createMoneySource(page, name, kind = 'wallet') {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption(kind);
  await page.locator('#money_source_active').check();
  await page.locator('form input[type="submit"]').click();
  await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();
}

test.describe('AI expense detection selects the money source', () => {
  test('pre-selects the source mentioned by name in the detected expense row', async ({ page }) => {
    await signUp(page);
    await createMoneySource(page, 'Nequi', 'wallet');

    await page.goto('/expenses');
    await page.getByTestId('ai-text-input').fill('Gasté 50 mil en almuerzo desde nequi');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
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
    const row = page.locator('[data-testid="recognition-row"]', { hasText: 'Visa' });
    await row.locator('[data-testid="edit-recognition"]').click();
    await expect(page.getByTestId('recognition-edit-panel')).toBeVisible();
    await page.locator('[data-recognition-chips="keywords"] [data-recognition-add]').click();
    const keywordInput = page.locator('[data-recognition-inline-add="keywords"]');
    await keywordInput.fill('tarjeta clásica');
    await keywordInput.press('Enter');
    await page.getByTestId('recognition-save').click();
    await expect(page.getByText('Configuración de reconocimiento guardada.')).toBeVisible();

    await page.goto('/expenses');
    await page.getByTestId('ai-text-input').fill('Pag 50 mil en el restaurante con la tarjeta clásica');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
    await expect(page.getByTestId('ai-row')).toHaveCount(1);

    const sourceSelect = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelect.locator('option:checked')).toHaveText('Visa');
  });

  test('leaves the source unselected when no source is mentioned in the text', async ({ page }) => {
    await signUp(page);
    await createMoneySource(page, 'Nequi', 'wallet');

    await page.goto('/expenses');
    await page.getByTestId('ai-text-input').fill('Gasté 50 mil en almuerzo');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
    await expect(page.getByTestId('ai-row')).toHaveCount(1);

    const sourceSelect = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelect.locator('option:checked')).toHaveText('Ninguno');
  });

  test('applies the mentioned source to every detected expense row', async ({ page }) => {
    await signUp(page);
    await createMoneySource(page, 'Nequi', 'wallet');

    await page.goto('/expenses');
    await page.getByTestId('ai-text-input').fill('Gasté 50 mil en restaurante y 20 mil en parqueadero desde nequi');
    await page.getByTestId('ai-parse-button').click();

    await expect(page.getByTestId('ai-preview-modal')).toBeVisible();
    await expect(page.getByTestId('ai-row')).toHaveCount(2);

    const sourceSelects = page.locator('[data-testid="ai-row"] .ai-field-source');
    await expect(sourceSelects).toHaveCount(2);
    for (let i = 0; i < 2; i++) {
      await expect(sourceSelects.nth(i).locator('option:checked')).toHaveText('Nequi');
    }
  });
});
