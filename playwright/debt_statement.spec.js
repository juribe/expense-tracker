const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const {
  createMoneySource,
  createCreditCard,
  createLoan
} = require('./helpers/money_sources');

test.describe('Debt statement (extracto de deuda)', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  function todayInput() {
    const now = new Date();
    const day = String(now.getDate()).padStart(2, '0');
    const month = String(now.getMonth() + 1).padStart(2, '0');
    return `${day}/${month}/${now.getFullYear()}`;
  }

  async function showPath(page, testId, name) {
    const source = page.locator(`[data-testid="${testId}"]`, { hasText: name }).first();
    const link = source.getByRole('link', { name }).first();
    return link.getAttribute('href');
  }

  async function createExpense(page, { amount, description, moneySourceId }) {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill(amount);
    await page.locator('#expense_date').fill(todayInput());
    await page.locator('#expense_description').fill(description);
    await page.locator('#expense_money_source_id').selectOption(moneySourceId);
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.locator('#expenseTable', { hasText: description })).toBeVisible();
  }

  async function applyPayment(page, sourcePath, expenseDescription) {
    await page.goto(sourcePath);
    await page.locator('[data-tab-slug="pagos"]').click();

    const option = page.locator('#pickExpense option', { hasText: expenseDescription });
    const expenseId = await option.getAttribute('value');
    await page.locator('#pickExpense').selectOption(expenseId);
    await page.getByRole('button', { name: 'Continuar' }).click();

    await expect(page).toHaveURL(/\/payments\/new/);
    await page.getByRole('button', { name: 'Aplicar pago' }).click();
    await expect(page).toHaveURL(/\/money_sources\/[0-9a-f-]{36}$/);
  }

  async function openExtractFromShow(page, sourcePath) {
    await page.goto(sourcePath);
    await page.locator('[data-tab-slug="movimientos"]').click();
    await expect(page).toHaveURL(new RegExp(`${sourcePath}/extractos$`));
    await expect(page.locator('#movementRows')).toBeVisible();
  }

  test('credit card extract shows purchases and payments with debt terminology', async ({ page }) => {
    const accountName = `Cuenta TC-${Date.now()}`;
    const cardName = `TDC Extracto-${Date.now()}`;
    const purchase = `Compra TC ${Date.now()}`;
    const payment = `Pago TC ${Date.now()}`;

    await createMoneySource(page, accountName, 'account', { startingBalance: '1000000' });
    const accountPath = await showPath(page, 'account-card', accountName);
    await createCreditCard(page, cardName);
    const cardPath = await showPath(page, 'credit-card-card', cardName);
    const cardId = cardPath.split('/').pop();

    await createExpense(page, { amount: '300000', description: purchase, moneySourceId: cardId });
    await createExpense(page, { amount: '200000', description: payment, moneySourceId: accountPath.split('/').pop() });
    await applyPayment(page, cardPath, payment);
    await openExtractFromShow(page, cardPath);

    const summary = page.locator('.card', { hasText: 'Resumen del período' }).first();
    await expect(summary.getByText('Pagos', { exact: true })).toBeVisible();
    await expect(summary.getByText('Compras', { exact: true })).toBeVisible();

    const purchaseRow = page.locator('.statement-row', { hasText: purchase });
    await expect(purchaseRow).toHaveAttribute('data-type', 'Compra');
    await expect(purchaseRow).toHaveAttribute('data-direction', 'out');

    const paymentRow = page.locator('.statement-row', { hasText: payment });
    await expect(paymentRow).toHaveAttribute('data-type', 'Pago');
    await expect(paymentRow).toHaveAttribute('data-direction', 'in');
  });

  test('revolving loan extract labels a disbursement as a transfer', async ({ page }) => {
    const loanName = `Rotativo Extracto-${Date.now()}`;
    const accountName = `Cuenta Rotativo-${Date.now()}`;

    await createMoneySource(page, accountName, 'account', { startingBalance: '0' });
    const accountPath = await showPath(page, 'account-card', accountName);
    await createLoan(page, loanName, { subKind: 'revolving', principal: '5000000' });
    const loanPath = await showPath(page, 'loan-card', loanName);
    const loanId = loanPath.split('/').pop();

    await page.goto(`/transfers/quick_new?from_source_id=${loanId}&mode=disburse&return_to=${encodeURIComponent(loanPath)}`);
    await expect(page.locator('[data-testid="quick-transfer-form"]')).toBeVisible();
    await page.locator('#transfer_to_source_id').selectOption(accountPath.split('/').pop());
    await page.locator('#transfer_amount').fill('400000');
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();
    await expect(page).toHaveURL(new RegExp(`${loanPath}$`));

    await openExtractFromShow(page, loanPath);

    const summary = page.locator('.card', { hasText: 'Resumen del período' }).first();
    await expect(summary.getByText('Pagos', { exact: true })).toBeVisible();
    await expect(summary.getByText('Usos y transferencias', { exact: true })).toBeVisible();

    const transferRow = page.locator('.statement-row').first();
    await expect(transferRow).toHaveAttribute('data-type', 'Transferencia');
    await expect(transferRow).toHaveAttribute('data-direction', 'out');
  });

  test('normal loan extract labels a payment and the cargo summary', async ({ page }) => {
    const loanName = `Préstamo Extracto-${Date.now()}`;
    const accountName = `Cuenta Préstamo-${Date.now()}`;
    const payment = `Cuota préstamo ${Date.now()}`;

    await createMoneySource(page, accountName, 'account', { startingBalance: '1000000' });
    const accountPath = await showPath(page, 'account-card', accountName);
    await createLoan(page, loanName, { subKind: 'personal', principal: '1000000' });
    const loanPath = await showPath(page, 'loan-card', loanName);

    await createExpense(page, { amount: '200000', description: payment, moneySourceId: accountPath.split('/').pop() });
    await applyPayment(page, loanPath, payment);
    await openExtractFromShow(page, loanPath);

    const summary = page.locator('.card', { hasText: 'Resumen del período' }).first();
    await expect(summary.getByText('Pagos', { exact: true })).toBeVisible();
    await expect(summary.getByText('Cargos', { exact: true })).toBeVisible();

    const paymentRow = page.locator('.statement-row', { hasText: payment });
    await expect(paymentRow).toHaveAttribute('data-type', 'Pago');
    await expect(paymentRow).toHaveAttribute('data-direction', 'in');
  });
});
