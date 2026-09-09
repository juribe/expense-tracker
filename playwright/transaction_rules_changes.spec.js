const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('suggested rules – dismiss and create from suggestion', () => {
  async function createExpense(page, category, description) {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('50.00');
    await page.locator('#expense_date').fill('2023-11-15');
    await page.locator('#expense_description').fill(description);
    await page.locator('#expense_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses$/);
  }

  async function createSuggestionData(page) {
    const category = `Gym-${Date.now()}`;
    await createCategory(page, category);
    for (let i = 0; i < 5; i += 1) {
      await createExpense(page, category, 'smartfit bogotá');
    }
    return category;
  }

  test('suggested rule panel shows a Descartar button and dismiss persists', async ({ page }) => {
    await signUp(page);
    await createSuggestionData(page);

    await page.goto('/transaction_rules');
    const panel = page.locator('section#suggested-rules');
    await expect(panel).toBeVisible();
    await expect(panel).toContainText('Reglas sugeridas');
    await expect(panel.locator('form button', { hasText: 'Descartar' }).first()).toBeVisible();

    await panel.locator('form button', { hasText: 'Descartar' }).first().click();
    await expect(page.getByText('Sugerencia descartada.')).toBeVisible();
    await expect(page.locator('section#suggested-rules')).toHaveCount(0);

    await page.reload();
    await expect(page.locator('section#suggested-rules')).toHaveCount(0);
  });

  test('creating a rule from a suggestion makes the suggestion disappear', async ({ page }) => {
    await signUp(page);
    const category = await createSuggestionData(page);

    await page.goto('/transaction_rules');
    await page.locator('section#suggested-rules').getByRole('link', { name: /Crear regla/i }).first().click();
    await expect(page).toHaveURL(/\/transaction_rules\/new/);
    await expect(page.locator('#transaction_rule_merchant_contains')).toHaveValue(/smartfit bogot/);

    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);
    await expect(page.locator('section#suggested-rules')).toHaveCount(0);
    await expect(page.locator('.card', { hasText: /smartfit bogot/i })).toBeVisible();
    await expect(page.locator('.card', { hasText: /smartfit bogot/i })).toContainText(category);
  });
});

test.describe('editing a rule – changing condition and action type', () => {
  async function createMerchantRule(page, category, merchant) {
    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill(merchant);
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);
  }

  test('changing the condition type replaces the old condition', async ({ page }) => {
    await signUp(page);
    const category = `Rent-${Date.now()}`;
    await createCategory(page, category);
    await createMerchantRule(page, category, 'SMARTFIT');

    const card = page.locator('.card', { hasText: 'SMARTFIT' });
    await expect(card).toBeVisible();

    await card.getByRole('link', { name: /Editar/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules\/\d+\/edit/);
    await page.locator('#condition_field').selectOption('description_contains');
    await page.locator('#transaction_rule_description_contains').fill('renta');
    await page.getByRole('button', { name: /Guardar cambios/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const editedCard = page.locator('.card', { hasText: 'renta' });
    await expect(editedCard).toBeVisible();
    await expect(editedCard).toContainText('La descripción contiene');
    await expect(editedCard).not.toContainText('SMARTFIT');
  });

  test('changing the action type replaces the old action', async ({ page }) => {
    await signUp(page);
    const category = `Tags-${Date.now()}`;
    await createCategory(page, category);
    await createMerchantRule(page, category, 'UBER');

    const card = page.locator('.card', { hasText: 'UBER' });
    await card.getByRole('link', { name: /Editar/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules\/\d+\/edit/);
    await page.locator('#action_field').selectOption('tag');
    await page.locator('#transaction_rule_tag').fill('Transporte');
    await page.getByRole('button', { name: /Guardar cambios/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const editedCard = page.locator('.card', { hasText: 'Transporte' });
    await expect(editedCard).toBeVisible();
    await expect(editedCard).toContainText('Etiqueta');
    await expect(editedCard).not.toContainText(category);
  });
});
