const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('Debt payments', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('applying a payment from another expense submits the form and returns to the debt', async ({ page }) => {
    const cardName = `TDC Pago-${Date.now()}`;
    const accountName = `Cuenta Pago-${Date.now()}`;
    const expenseDescription = `Pago TC ${Date.now()}`;

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(accountName);
    await page.locator('#money_source_kind').selectOption('account');
    await page.locator('[data-kind-panel~="account"] #money_source_starting_balance').fill('1000000');
    await page.locator('#money_source_active').first().check();
    await page.locator('form input[type="submit"]').click();
    await expect(page).toHaveURL(/\/money_sources/);

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(cardName);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_credit_account_attributes_card_brand').selectOption('visa');
    await page.locator('#money_source_credit_account_attributes_card_last_four').fill('9876');
    await page.locator('#money_source_credit_account_attributes_credit_limit').fill('20000000');
    await page.locator('#money_source_credit_account_attributes_statement_day').fill('15');
    await page.locator('#money_source_credit_account_attributes_payment_due_day').fill('30');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();
    await expect(page).toHaveURL(/\/money_sources\/credit_cards$/);

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('150000');
    await page.locator('#expense_date').fill('15/10/2026');
    await page.locator('#expense_description').fill(expenseDescription);
    await page.locator('#expense_money_source_id').selectOption({ label: accountName });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.locator('#expenseTable', { hasText: expenseDescription })).toBeVisible();

    await page.goto('/money_sources');
    await page.getByRole('link', { name: cardName }).click();
    await page.locator('[data-tab-slug="pagos"]').click();

    const expenseOption = page.locator('#pickExpense option', { hasText: expenseDescription });
    const expenseId = await expenseOption.getAttribute('value');
    await page.locator('#pickExpense').selectOption(expenseId);
    await page.getByRole('button', { name: 'Continuar' }).click();

    await expect(page).toHaveURL(/\/payments\/new/);
    await page.getByRole('button', { name: 'Aplicar pago' }).click();

    await expect(page).toHaveURL(/\/money_sources\/[0-9a-f-]{36}$/);
    await expect(page.getByText(/Pago de .* aplicado a/)).toBeVisible();
  });
});
