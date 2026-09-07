const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('automatic rules (reglas automáticas)', () => {
  test('user can create a rule and it is listed on the rules page', async ({ page }) => {
    await signUp(page);
    const category = `Automation-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules');
    await expect(page.getByRole('heading', { name: /\bReglas\b/ })).toBeVisible();

    await page.getByRole('link', { name: /Nueva regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules\/new/);

    await page.locator('#transaction_rule_merchant_contains').fill('SMARTFIT');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();

    await expect(page).toHaveURL(/\/transaction_rules$/);
    await expect(page.getByText('La regla se creó correctamente.')).toBeVisible();
    const card = page.locator('.card', { hasText: 'SMARTFIT' });
    await expect(card).toBeVisible();
    await expect(card).toContainText(category);
  });

  test('a rule auto-categorizes a matching expense on creation', async ({ page }) => {
    await signUp(page);
    const category = `Gym-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('SMARTFIT');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('45.20');
    await page.locator('#expense_date').fill('2023-11-15');
    await page.locator('#expense_description').fill('SMARTFIT Bogotá');
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses$/);

    const row = page.locator('#expenseTable tr', { hasText: 'SMARTFIT Bogotá' });
    await expect(row).toBeVisible();
    await expect(row).toContainText(category);
  });

  test('user can toggle, edit and delete a rule', async ({ page }) => {
    await signUp(page);
    const category = `Toggle-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('UBER');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const card = page.locator('.card', { hasText: 'UBER' });
    await expect(card).toContainText('Habilitada');

    await card.locator('input[role="switch"]').uncheck();
    await expect(card.locator('.badge', { hasText: 'Deshabilitada' })).toBeVisible();

    await page.locator('.card', { hasText: 'UBER' }).getByRole('link', { name: /Editar/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules\/\d+\/edit/);
    await page.locator('#transaction_rule_merchant_contains').fill('RAPPI');
    await page.getByRole('button', { name: /Guardar cambios/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);
    await expect(page.locator('.card', { hasText: 'RAPPI' })).toBeVisible();

    page.on('dialog', (dialog) => dialog.accept());
    await page.locator('.card', { hasText: 'RAPPI' }).getByRole('button', { name: /Eliminar/i }).click();
    await expect(page.getByText('La regla se eliminó correctamente.')).toBeVisible();
    await expect(page.locator('.card', { hasText: 'RAPPI' })).toHaveCount(0);
  });
});
