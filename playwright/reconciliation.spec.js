const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');

async function createAccount(page, name, startingBalance) {
  await page.goto('/money_sources/new');
  await page.locator('input[name="money_source[name]"]').fill(name);
  await page.locator('#money_source_kind').selectOption({ label: 'Cuenta' });
  await page.locator('input[name="money_source[starting_balance]"]').fill(startingBalance);
  await page.locator('form input[type="submit"]').first().click();
  await expect(page).not.toHaveURL(/\/money_sources\/new(\?|$)/);
}

async function createExpenseTemplate(page, category, { description, amount, day }) {
  await page.goto('/recurring_templates?kind=expense');
  await page.getByTestId('add-recurring').click();
  await expect(page.getByTestId('form-modal')).toBeVisible();
  await pickCategory(page, 'recurring_template_category_id', category);
  await page.locator('#recurring_template_kind').selectOption('expense');
  await page.locator('#recurring_template_description').fill(description);
  await page.locator('#recurring_template_amount').fill(amount);
  await page.locator('#recurring_template_payment_day').fill(String(day));
  await page.getByTestId('save-recurring').click();
  await expect(page.getByTestId('recurring-row').filter({ hasText: description })).toBeVisible();
}

test.describe('día de cuadre', () => {
  test('dashboard loads from the sidebar and unverified accounts are neutral', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'Davibank Cuadre Primer', '500.000');
    await page.goto('/dashboard');
    await page.locator('a[href="/reconciliation"]').click();
    await expect(page).toHaveURL(/\/reconciliation/);
    await expect(page.getByRole('heading', { name: 'Día de Cuadre' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Pagos pendientes' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Saldos por conciliar' })).toBeVisible();
    const row = page.locator('li.list-group-item').filter({ hasText: 'Davibank Cuadre Primer' });
    await expect(row.getByText('Sin verificar').first()).toBeVisible();
  });

  test('reconcile modal records the real balance and resolves the row', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'Davibank Cuadre', '8.400.000');

    await page.goto('/reconciliation');
    const row = page.locator('li.list-group-item').filter({ hasText: 'Davibank Cuadre' });
    await expect(row).toBeVisible();
    await expect(row.getByText('Sin verificar').first()).toBeVisible();

    await row.getByRole('button', { name: 'Conciliar' }).click();
    await expect(page.locator('#reconcileModal')).toBeVisible();
    await expect(page.locator('#reconcileModal .js-source-name')).toHaveText('Davibank Cuadre');

    await page.locator('#reconcileActualBalance').fill('8.450.000');
    await expect(page.locator('#reconcileModal .js-difference')).toContainText('50.000');

    await page.locator('#reconcileAdjust').click();

    await expect(page).toHaveURL(/\/reconciliation/);
    const settledRow = page.locator('li.list-group-item').filter({ hasText: 'Davibank Cuadre' });
    await expect(settledRow.getByText('Cuadrado')).toBeVisible();
    await expect(settledRow.getByText('$8.450.000').first()).toBeVisible();
  });

  test('assign an existing expense to a pending recurring payment', async ({ page }) => {
    const category = `Cuadre-${Date.now()}`;
    await signUp(page);
    await createCategory(page, category);
    await createExpenseTemplate(page, category, { description: 'Crédito carro Cuadre', amount: '2818000', day: 5 });

    // Create the matching expense via the normal creation flow.
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('2818000');
    await pickCategory(page, 'expense_category_id', category);
    await page.locator('#expense_description').fill('Pago crédito carro Cuadre');
    const submit = page.locator('form input[type="submit"], form button[type="submit"]').first();
    await submit.click();
    await expect(page).toHaveURL(/\/expenses/);

    await page.goto('/reconciliation');
    const pendingRow = page.locator('li.list-group-item').filter({ hasText: 'Crédito carro Cuadre' });
    await expect(pendingRow).toBeVisible();

    await pendingRow.getByRole('button', { name: 'Asignar' }).click();
    await expect(page.locator('#assignPaymentModal')).toBeVisible();
    await expect(page.locator('#assignPaymentModal .js-payment-name')).toHaveText('Crédito carro Cuadre');

    const results = page.locator('#assignExpenseResults .js-assign-result');
    await expect(results.filter({ hasText: 'Pago crédito carro Cuadre' })).toBeVisible();
    await results.first().click();
    await page.locator('#assignPaymentSubmit').click();

    await expect(page).toHaveURL(/\/reconciliation/);
    await expect(page.locator('li.list-group-item').filter({ hasText: 'Crédito carro Cuadre' })).not.toBeVisible();
    await expect(page.getByText(/Todo cuadrado/).first()).toBeVisible();
  });

  test('todo está bien confirms the balance and the adjustment is traceable + reversible', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'AllGood Bank', '2.000.000');

    await page.goto('/reconciliation');
    const row = page.locator('li.list-group-item').filter({ hasText: 'AllGood Bank' });

    // "Todo está bien" marks the row reconciled without any balance change.
    await row.getByRole('button', { name: 'Conciliar' }).click();
    await page.locator('#reconcileAllGood').click();
    await expect(row.getByText('Cuadrado')).toBeVisible();

    // A real adjustment with a note shows the audit trace on the account page.
    await row.getByRole('button', { name: 'Conciliar' }).click();
    await page.locator('#reconcileActualBalance').fill('2.100.000');
    await page.locator('#reconcileNote').fill('Pago por fuera de la app');
    await page.locator('#reconcileAdjust').click();
    // The flash only exists after the post-action reload completes.
    await expect(page.getByText('Saldo registrado.')).toBeVisible();
    await page.waitForLoadState('load');

    await page.goto('/money_sources');
    await page.locator('a[href^="/money_sources/"]').filter({ hasText: 'AllGood Bank' }).first().click();
    await expect(page.getByText('Ajuste manual', { exact: true })).toBeVisible();
    await expect(page.getByText('Pago por fuera de la app')).toBeVisible();

    // Reverting restores the original balance and hides the trace.
    page.once('dialog', d => d.accept());
    await page.getByRole('button', { name: /Revertir ajuste/ }).click();
    await expect(page.getByText('Ajuste manual revertido')).toBeVisible();
    await expect(page.getByText('Ajuste manual', { exact: true })).not.toBeVisible();
    await expect(page.getByText('$2.000.000').first()).toBeVisible();
  });
});
