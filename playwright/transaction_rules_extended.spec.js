const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

async function createExpense(page, { amount, description, date }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(String(amount));
  await page.locator('#expense_date').fill(date || '2025-06-15');
  await page.locator('#expense_description').fill(description);
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).toHaveURL(/\/expenses$/);
}

test.describe('automatic rules – extended scenarios', () => {

  test('rule with description_contains matches expense', async ({ page }) => {
    await signUp(page);
    const category = `DescCat-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('description_contains');
    await page.locator('#transaction_rule_description_contains').fill('NETFLIX');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await createExpense(page, { amount: 15.99, description: 'Netflix subscription' });

    const row = page.locator('#expenseTable tr', { hasText: 'Netflix subscription' });
    await expect(row).toContainText(category);
  });

  test('rule with tag action adds a tag to matching expense', async ({ page }) => {
    await signUp(page);
    const category = `TagCat-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('SPOTIFY');
    await page.locator('#action_field').selectOption('tag');
    await page.locator('#transaction_rule_tag').fill('Subscriptions');
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const card = page.locator('.card', { hasText: 'SPOTIFY' });
    await expect(card).toContainText('Etiqueta');
    await expect(card).toContainText('Subscriptions');

    await createExpense(page, { amount: 9.99, description: 'SPOTIFY Premium' });

    const row = page.locator('#expenseTable tr', { hasText: 'SPOTIFY Premium' });
    await expect(row).toBeVisible();
  });

  test('rule with amount_gt condition only matches large expenses', async ({ page }) => {
    await signUp(page);
    const category = `BigSpend-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('amount_gt');
    await page.locator('#transaction_rule_amount_gt').fill('500');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    const card = page.locator('.card', { hasText: 'Monto mayor que' });
    await expect(card).toBeVisible();

    await createExpense(page, { amount: 750.00, description: 'Expensive gadget' });

    const row = page.locator('#expenseTable tr', { hasText: 'Expensive gadget' });
    await expect(row).toContainText(category);
  });

  test('rule with amount_lt condition only matches small expenses', async ({ page }) => {
    await signUp(page);
    const category = `SmallSpend-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('amount_lt');
    await page.locator('#transaction_rule_amount_lt').fill('20');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await createExpense(page, { amount: 5.50, description: 'Coffee shop' });

    const row = page.locator('#expenseTable tr', { hasText: 'Coffee shop' });
    await expect(row).toContainText(category);
  });

  test('multiple rules can match the same transaction', async ({ page }) => {
    await signUp(page);
    const catA = `MultiA-${Date.now()}`;
    const catB = `MultiB-${Date.now()}`;
    await createCategory(page, catA);
    await createCategory(page, catB);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('COMBO');
    await page.locator('#transaction_rule_category_id').selectOption({ label: catA });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await page.goto('/transaction_rules/new');
    await page.locator('#condition_field').selectOption('description_contains');
    await page.locator('#transaction_rule_description_contains').fill('COMBO');
    await page.locator('#action_field').selectOption('tag');
    await page.locator('#transaction_rule_tag').fill('ComboTag');
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await expect(page.locator('.card', { hasText: 'COMBO' })).toHaveCount(2);

    await createExpense(page, { amount: 30.00, description: 'COMBO meal deal' });

    const row = page.locator('#expenseTable tr', { hasText: 'COMBO meal deal' });
    await expect(row).toContainText(catA);
  });

  test('user can manually override a rule-applied category', async ({ page }) => {
    await signUp(page);
    const ruleCategory = `Auto-${Date.now()}`;
    const manualCategory = `Manual-${Date.now()}`;
    await createCategory(page, ruleCategory);
    await createCategory(page, manualCategory);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('GASSTATION');
    await page.locator('#transaction_rule_category_id').selectOption({ label: ruleCategory });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await createExpense(page, { amount: 40.00, description: 'GASSTATION fill up' });

    const row = page.locator('#expenseTable tr', { hasText: 'GASSTATION fill up' });
    await expect(row).toContainText(ruleCategory);

    await page.locator('#expenseTable tr', { hasText: 'GASSTATION fill up' }).getByRole('link').click();
    await expect(page).toHaveURL(/\/expenses\/\d+\/edit/);

    await page.locator('#expense_category_id').selectOption({ label: manualCategory });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);

    const updatedRow = page.locator('#expenseTable tr', { hasText: 'GASSTATION fill up' });
    await expect(updatedRow).toContainText(manualCategory);
  });

  test('expense with no matching rule remains uncategorized', async ({ page }) => {
    await signUp(page);
    const category = `NoMatch-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('SPECIFIC_MERCHANT');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();
    await expect(page).toHaveURL(/\/transaction_rules$/);

    await createExpense(page, { amount: 25.00, description: 'Random coffee shop' });

    const row = page.locator('#expenseTable tr', { hasText: 'Random coffee shop' });
    await expect(row).toBeVisible();
    await expect(row).not.toContainText(category);
  });

  test('rule form validates at least one condition is required', async ({ page }) => {
    await signUp(page);
    const category = `ValidCat-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_category_id').selectOption({ label: category });
    await page.getByRole('button', { name: /Guardar regla/i }).click();

    await expect(page.locator('#error-summary')).toBeVisible();
  });

  test('rule form validates at least one action is required', async ({ page }) => {
    await signUp(page);

    await page.goto('/transaction_rules/new');
    await page.locator('#transaction_rule_merchant_contains').fill('TEST');
    await page.getByRole('button', { name: /Guardar regla/i }).click();

    await expect(page.locator('#error-summary')).toBeVisible();
  });

  test('rules index shows empty state when no rules exist', async ({ page }) => {
    await signUp(page);

    await page.goto('/transaction_rules');
    await expect(page.getByText('Aún no tienes reglas')).toBeVisible();
    await expect(page.getByText('Crea tu primera regla')).toBeVisible();
  });

  test('condition field dropdown switches visible input', async ({ page }) => {
    await signUp(page);

    await page.goto('/transaction_rules/new');

    await page.locator('#condition_field').selectOption('merchant_contains');
    await expect(page.locator('[data-condition-input="merchant_contains"]')).toBeVisible();
    await expect(page.locator('[data-condition-input="description_contains"]')).toHaveClass(/d-none/);

    await page.locator('#condition_field').selectOption('description_contains');
    await expect(page.locator('[data-condition-input="description_contains"]')).toBeVisible();
    await expect(page.locator('[data-condition-input="merchant_contains"]')).toHaveClass(/d-none/);

    await page.locator('#condition_field').selectOption('amount_gt');
    await expect(page.locator('[data-condition-input="amount_gt"]')).toBeVisible();
    await expect(page.locator('[data-condition-input="description_contains"]')).toHaveClass(/d-none/);
  });

  test('action field dropdown switches visible input', async ({ page }) => {
    await signUp(page);

    await page.goto('/transaction_rules/new');

    await page.locator('#action_field').selectOption('category');
    await expect(page.locator('[data-action-input="category"]')).toBeVisible();
    await expect(page.locator('[data-action-input="tag"]')).toHaveClass(/d-none/);

    await page.locator('#action_field').selectOption('tag');
    await expect(page.locator('[data-action-input="tag"]')).toBeVisible();
    await expect(page.locator('[data-action-input="category"]')).toHaveClass(/d-none/);

    await page.locator('#action_field').selectOption('money_source');
    await expect(page.locator('[data-action-input="money_source"]')).toBeVisible();
    await expect(page.locator('[data-action-input="tag"]')).toHaveClass(/d-none/);
  });
});
