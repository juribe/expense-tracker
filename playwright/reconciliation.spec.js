const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');
const { createMoneySource, createLoan } = require('./helpers/money_sources');

async function createAccount(page, name, startingBalance) {
  await page.goto('/money_sources/new');
  await page.locator('input[name="money_source[name]"]').fill(name);
  await page.locator('#money_source_kind').selectOption({ label: 'Cuenta' });
  await page.locator('[data-kind-panel~="account"] input[name="money_source[starting_balance]"]').fill(startingBalance);
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

async function createExpense(page, { category, description, amount, sourceLabel }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(amount);
  await pickCategory(page, 'expense_category_id', category);
  await page.locator('#expense_description').fill(description);
  await page.locator('#expense_money_source_id').selectOption({ label: sourceLabel });
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).toHaveURL(/\/expenses/);
}

test.describe('día de balance', () => {
  test('dashboard loads from the sidebar and unverified accounts are neutral', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'Davibank Cuadre Primer', '500.000');
    await page.goto('/reconciliation');
    await expect(page).toHaveURL(/\/reconciliation/);
    await expect(page.getByRole('heading', { name: 'Día de Balance' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Saldos de tus cuentas' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Pagos recurrentes sin pagar' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Obligaciones por verificar' })).toBeVisible();
    const row = page.getByTestId('account-row').filter({ hasText: 'Davibank Cuadre Primer' });
    await expect(row.getByText('Por verificar').first()).toBeVisible();
    await expect(row.getByRole('button', { name: 'Movimientos' })).toBeVisible();
    await expect(row.getByRole('button', { name: 'Verificar saldo' })).toBeVisible();

    const accountsPanel = page.locator('.rec-panel').filter({ hasText: 'Saldos de tus cuentas' });
    const paymentsPanel = page.locator('.rec-panel').filter({ hasText: 'Pagos recurrentes sin pagar' });
    const accountsBox = await accountsPanel.boundingBox();
    const paymentsBox = await paymentsPanel.boundingBox();
    expect(accountsBox.width).toBeCloseTo(paymentsBox.width, 0);
    expect(paymentsBox.y).toBeGreaterThan(accountsBox.y);
  });

  test('reconcile modal records the real balance and resolves the row', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'Davibank Cuadre', '8.400.000');

    await page.goto('/reconciliation');
    const row = page.getByTestId('account-row').filter({ hasText: 'Davibank Cuadre' });
    await expect(row).toBeVisible();
    await expect(row.getByText('Por verificar').first()).toBeVisible();

    await row.getByRole('button', { name: 'Verificar saldo' }).click();
    await expect(page.locator('#reconcileModal')).toBeVisible();
    await expect(page.locator('#reconcileModal .js-source-name')).toHaveText('Davibank Cuadre');

    await page.locator('#reconcileActualBalance').fill('8.450.000');
    await expect(page.locator('#reconcileModal .js-difference')).toContainText('50.000');

    await page.locator('#reconcileAdjust').click();

    await expect(page).toHaveURL(/\/reconciliation/);
    const settledRow = page.getByTestId('account-row').filter({ hasText: 'Davibank Cuadre' });
    await expect(settledRow.getByText('Verificada')).toBeVisible();
    await expect(settledRow.getByText('$8.450.000').first()).toBeVisible();
    await expect(settledRow.getByRole('button', { name: 'Cambiar saldo' })).toBeVisible();
  });

  test('movements button opens the source-scoped movement list', async ({ page }) => {
    const category = `Movimientos-${Date.now()}`;
    await signUp(page);
    await createCategory(page, category);
    const account = await createMoneySource(page, `Cuenta-${Date.now()}`, 'account', { startingBalance: '5000000' });
    const other = await createMoneySource(page, `Otra-${Date.now()}`, 'account', { startingBalance: '5000000' });
    await createExpense(page, { category, description: 'Movimiento propio', amount: '150000', sourceLabel: account });
    await createExpense(page, { category, description: 'Movimiento ajeno', amount: '150000', sourceLabel: other });

    await page.goto('/reconciliation');
    const row = page.getByTestId('account-row').filter({ hasText: account });
    await row.getByRole('button', { name: 'Movimientos' }).click();
    await expect(page.locator('#reconcileModal')).toBeVisible();
    await expect(page.locator('#reconcileSearchResults')).toContainText('Movimiento propio');
    await expect(page.locator('#reconcileSearchResults')).not.toContainText('Movimiento ajeno');
    await expect(page.locator('#reconcileSearchInput')).toBeVisible();
    await expect(page.locator('#reconcileLoadMore')).toBeAttached();
  });

  test('assign an existing expense to a pending recurring payment', async ({ page }) => {
    const category = `Cuadre-${Date.now()}`;
    await signUp(page);
    await createCategory(page, category);
    await createExpenseTemplate(page, category, { description: 'Crédito carro Cuadre', amount: '2818000', day: 5 });

    // Create the matching expense via the normal creation flow.
    // The expense of this flow is ~2.8M, above the default helper balance.
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`, 'cash', { startingBalance: '5000000' });
    await createExpense(page, { category, description: 'Pago crédito carro Cuadre', amount: '2818000', sourceLabel: efectivo });

    await page.goto('/reconciliation');
    const pendingRow = page.getByTestId('pending-payment-row').filter({ hasText: 'Crédito carro Cuadre' });
    await expect(pendingRow).toBeVisible();

    await pendingRow.getByRole('button', { name: 'Asignar pago' }).click();
    await expect(page.locator('#assignPaymentModal')).toBeVisible();
    await expect(page.locator('#assignPaymentModal .js-payment-name')).toHaveText('Crédito carro Cuadre');
    await expect(page.locator('#assignPaymentModal')).not.toContainText('Sync Gmail');
    await expect(page.locator('#assignPaymentModal .js-payment-category')).toHaveText(category);

    const results = page.locator('#assignExpenseResults .js-assign-result');
    await expect(results.filter({ hasText: 'Pago crédito carro Cuadre' })).toBeVisible();
    await expect(results.filter({ hasText: 'Pago crédito carro Cuadre' }).getByText('Abrir')).toBeVisible();
    await results.first().click();
    await page.locator('#assignPaymentSubmit').click();

    await expect(page).toHaveURL(/\/reconciliation/);
    await expect(page.getByTestId('pending-payment-row').filter({ hasText: 'Crédito carro Cuadre' })).not.toBeVisible();

    // The status only reaches "Todo cuadrado" after every source balance is
    // verified: open the modal for the cash source and confirm it.
    await page.locator('.js-reconcile[data-mode="balance"]').first().click();
    await expect(page.locator('#reconcileModal')).toBeVisible();
    await page.locator('#reconcileAllGood').click();
    await page.waitForURL(/\/reconciliation/);

    await expect(page.getByText(/Todo cuadrado/).first()).toBeVisible();
  });

  test('todo está bien confirms the balance and the adjustment is traceable + reversible', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'AllGood Bank', '2.000.000');

    await page.goto('/reconciliation');
    const row = page.getByTestId('account-row').filter({ hasText: 'AllGood Bank' });

    // "Todo está bien" marks the row reconciled without any balance change.
    await row.getByRole('button', { name: 'Verificar saldo' }).click();
    await page.locator('#reconcileAllGood').click();
    await expect(row.getByText('Verificada')).toBeVisible();

    // A real adjustment with a note shows the audit trace on the account page.
    await row.getByRole('button', { name: 'Cambiar saldo' }).click();
    await page.locator('#reconcileActualBalance').fill('2.100.000');
    await page.locator('#reconcileNote').fill('Pago por fuera de la app');
    await page.locator('#reconcileAdjust').click();
    // The flash only exists after the post-action reload completes.
    await expect(page.getByText('Saldo registrado.')).toBeVisible();
    await page.waitForLoadState('load');

    await page.goto('/money_sources/cash');
    await page.locator('a[href^="/money_sources/"]').filter({ hasText: 'AllGood Bank' }).first().click();
    await expect(page.getByText('Ajuste manual', { exact: true })).toBeVisible();
    await expect(page.getByText('Pago por fuera de la app').first()).toBeVisible();

    // Reverting restores the original balance and hides the trace.
    page.once('dialog', d => d.accept());
    await page.getByRole('button', { name: /Revertir ajuste/ }).click();
    await expect(page.getByText('Ajuste manual revertido')).toBeVisible();
    await expect(page.getByText('Ajuste manual', { exact: true })).not.toBeVisible();
    await expect(page.getByText('$2.000.000').first()).toBeVisible();
  });

  test('debt sources use the obligations section and the debt modal', async ({ page }) => {
    await signUp(page);
    const loan = await createLoan(page, `Crédito-${Date.now()}`, { principal: '5000000' });

    await page.goto('/reconciliation');
    const row = page.getByTestId('debt-row').filter({ hasText: loan });
    await expect(row).toBeVisible();
    await expect(row.getByText('Deuda en Yogasto')).toBeVisible();
    await expect(row.getByRole('button', { name: 'Movimientos' })).toBeVisible();

    await row.getByRole('button', { name: 'Verificar saldo' }).click();
    await expect(page.locator('#reconcileModal')).toBeVisible();
    await expect(page.locator('#reconcileModal')).toContainText('Deuda en Yogasto');
    await expect(page.locator('#reconcileCreateExpense')).not.toBeVisible();
    await expect(page.locator('#reconcileCreateIncome')).not.toBeVisible();
  });

  test('account rows stay usable on a narrow viewport', async ({ page }) => {
    await signUp(page);
    await createAccount(page, 'Mobile Bank', '1.000.000');
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto('/reconciliation');

    const row = page.getByTestId('account-row').filter({ hasText: 'Mobile Bank' });
    await expect(row.getByRole('button', { name: 'Movimientos' })).toBeVisible();
    await expect(row.getByRole('button', { name: 'Verificar saldo' })).toBeVisible();

    const overflows = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
    expect(overflows).toBe(false);
  });
});
