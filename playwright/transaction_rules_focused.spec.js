const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

async function createExpense(page, { amount, description, date, moneySourceLabel }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(String(amount));
  await page.locator('#expense_date').fill(date || '2025-07-01');
  await page.locator('#expense_description').fill(description);
  if (moneySourceLabel) {
    await page.locator('#expense_money_source_id').selectOption({ label: moneySourceLabel });
  }
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).toHaveURL(/\/expenses$/);
}

async function createMoneySource(page, name) {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption('account');
  await page.locator('#money_source_starting_balance').fill('0');
  await page.locator('#money_source_active').check();
  await page.locator('form input[type="submit"]').click();
  await expect(page).not.toHaveURL(/\/money_sources\/new/);
}

test.describe('transaction rules – focused scenarios', () => {

  test('money_source_condition rule matches expense with matching source', async ({ page }) => {
    await signUp(page);
    const category = `SrcCat-${Date.now()}`;
    await createCategory(page, category);

    const sourceName = `TestCash-${Date.now()}`;
    await createMoneySource(page, sourceName);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('money_source_condition');
    await page.locator('#transaction_rule_money_source_condition_id').selectOption({ label: sourceName });
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const card = page.locator('.card', { hasText: sourceName });
    await expect(card).toContainText(category);

    await createExpense(page, { amount: 100.00, description: 'Groceries', moneySourceLabel: sourceName });

    const row = page.locator('#expenseTable tr', { hasText: 'Groceries' });
    await expect(row).toContainText(category);
  });

  test('money_source_condition rule does NOT match expense with different source', async ({ page }) => {
    await signUp(page);
    const category = `SrcNo-${Date.now()}`;
    await createCategory(page, category);

    const srcA = `CardA-${Date.now()}`;
    const srcB = `CardB-${Date.now()}`;
    await createMoneySource(page, srcA);
    await createMoneySource(page, srcB);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('money_source_condition');
    await page.locator('#transaction_rule_money_source_condition_id').selectOption({ label: srcA });
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await createExpense(page, { amount: 50.00, description: 'Different source', moneySourceLabel: srcB });

    const row = page.locator('#expenseTable tr', { hasText: 'Different source' });
    await expect(row).not.toContainText(category);
  });

  test('money_source action sets money source on matching expense', async ({ page }) => {
    await signUp(page);
    const sourceName = `AutoSource-${Date.now()}`;
    await createMoneySource(page, sourceName);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('GAS');
    await page.locator('#action_field').selectOption('money_source');
    await page.locator('#transaction_rule_action_money_source_id').selectOption({ label: sourceName });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const card = page.locator('.card', { hasText: 'GAS' });
    await expect(card).toContainText('Fuente de dinero');
    await expect(card).toContainText(sourceName);

    await createExpense(page, { amount: 30.00, description: 'GAS station visit' });

    const row = page.locator('#expenseTable tr', { hasText: 'GAS station visit' });
    await expect(row).toBeVisible();

    await row.getByRole('link').click();
    await expect(page).toHaveURL(/\/expenses\/\d+\/edit/);
    await expect(page.locator('#expense_money_source_id')).toHaveValue(await page.locator('#expense_money_source_id option', { hasText: sourceName }).getAttribute('value'));
  });

  test('toggle_active via switch sends PATCH and flips status', async ({ page }) => {
    await signUp(page);
    const category = `Tog-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('TOGGLE_TEST');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await expect(page.locator('.card', { hasText: 'TOGGLE_TEST' })).toContainText('Habilitada');

    await page.locator('.card', { hasText: 'TOGGLE_TEST' }).locator('input[role="switch"]').uncheck();
    await expect(page.locator('.card', { hasText: 'TOGGLE_TEST' })).toContainText('Deshabilitada');

    await page.locator('.card', { hasText: 'TOGGLE_TEST' }).locator('input[role="switch"]').check();
    await expect(page.locator('.card', { hasText: 'TOGGLE_TEST' })).toContainText('Habilitada');
  });

  test('duplicate application prevention – rule-applied category is not overwritten on edit', async ({ page }) => {
    await signUp(page);
    const category = `Dup-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('DUP_MERCHANT');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await createExpense(page, { amount: 25.00, description: 'DUP_MERCHANT store' });

    const row = page.locator('#expenseTable tr', { hasText: 'DUP_MERCHANT store' });
    await expect(row).toContainText(category);

    await row.getByRole('link').click();
    await expect(page).toHaveURL(/\/expenses\/\d+\/edit/);
    await page.locator('#expense_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);

    const updatedRow = page.locator('#expenseTable tr', { hasText: 'DUP_MERCHANT store' });
    await expect(updatedRow).toContainText(category);
  });

  test('rule card shows condition value and action line', async ({ page }) => {
    await signUp(page);
    const category = `LabelCat-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('STARBUCKS');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const card = page.locator('.card', { hasText: 'STARBUCKS' });
    await expect(card).toContainText('STARBUCKS');
    await expect(card).toContainText('El comercio contiene');
    await expect(card).toContainText('Categoría');
    await expect(card).toContainText(category);
  });

  test('edit form pre-fills existing condition and action', async ({ page }) => {
    await signUp(page);
    const categoryA = `PreA-${Date.now()}`;
    const categoryB = `PreB-${Date.now()}`;
    await createCategory(page, categoryA);
    await createCategory(page, categoryB);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('PRE_FILL');
    await page.locator('#transaction_rule_category_id').selectOption({ label: categoryA });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await page.locator('.card', { hasText: 'PRE_FILL' }).getByRole('link', { name: /Editar/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules\/\d+\/edit/);

    await expect(page.locator('#transaction_rule_merchant_contains')).toHaveValue('PRE_FILL');
    await expect(page.locator('#transaction_rule_category_id')).toHaveValue(/[0-9]+/);

    await page.locator('#transaction_rule_merchant_contains').fill('PRE_FILL_V2');
    await page.locator('#transaction_rule_category_id').selectOption({ label: categoryB });
    await page.getByRole('button', { name: /Guardar cambios/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await expect(page.locator('.card', { hasText: 'PRE_FILL_V2' })).toContainText(categoryB);
  });
});