const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const {
  createMoneySource,
  createCreditCard,
  createLoan
} = require('./helpers/money_sources');

async function showPath(page, testId, name) {
  const card = page.locator(`[data-testid="${testId}"]`, { hasText: name }).first();
  const link = card.getByRole('link', { name }).first();
  return (await link.getAttribute('href')).split('?')[0];
}

async function createExpenseChargedTo(page, { amount, description, moneySourceId }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(String(amount));
  await page.locator('#expense_description').fill(description);
  await page.locator('#expense_money_source_id').selectOption(moneySourceId);
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).toHaveURL(/\/expenses$/);
}

test.describe('extraordinary debt payments', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('a loan extra payment moves real money and shows in the history', async ({ page }) => {
    const accountName = `Cuenta Abono-${Date.now()}`;
    const loanName = `Préstamo Abono-${Date.now()}`;

    await createMoneySource(page, accountName, 'account', {
      startingBalance: '5000000',
      // The abono is a real debit, so the 4x1.000 would otherwise take 4.000
      // of the funding account. Exempting it isolates the abono amount.
      fill: async (page) => {
        await page.locator('[data-kind-panel~="account"] #money_source_gmf_exempt').check();
      }
    });
    await createLoan(page, loanName, {
      subKind: 'personal',
      principal: '12000000',
      fill: async (page) => {
        const loanPanel = page.locator('[data-kind-panel="loan"]');
        await loanPanel.locator('#money_source_credit_account_attributes_interest_rate').fill('1.8');
        await loanPanel.locator('#money_source_credit_account_attributes_interest_rate_type').selectOption('monthly');
        await loanPanel.locator('#money_source_credit_account_attributes_installment_amount').fill('500000');
        await loanPanel.locator('#money_source_credit_account_attributes_installment_count').fill('24');
        await loanPanel.locator('#money_source_credit_account_attributes_payment_frequency').selectOption('monthly');
        await loanPanel.locator('#money_source_credit_account_attributes_start_date').fill('2026-01-05');
      }
    });

    const loanPath = await showPath(page, 'loan-card', loanName);
    await page.goto(loanPath);
    await page.locator('[data-tab-slug="abonos"]').click();

    await page.locator('select[name="funding_money_source_id"]').selectOption({ label: accountName });
    await page.locator('input[name="extra_amount"]').fill('1000000');
    await page.locator('select[name="application_type"]').selectOption('reduce_term');
    await page.locator('input[name="note"]').fill('Abono de prueba');
    await page.getByRole('button', { name: 'Aplicar abono' }).click();

    await expect(page).toHaveURL(new RegExp(`${loanPath}$`));
    await expect(page.getByText('Abono aplicado al saldo del crédito. La proyección se actualizará.')).toBeVisible();

    await page.locator('[data-tab-slug="abonos"]').click();
    // The payment list (inactive "Pagos" tab) repeats the same description, so
    // scope the assertions to the visible abonos panel.
    const abonos = page.locator('#source-tab-abonos');
    await expect(abonos.getByText('Abono extraordinario').first()).toBeVisible();
    await expect(abonos.getByText('-$1.000.000').first()).toBeVisible();
    await expect(abonos.getByText('Abono de prueba')).toBeVisible();

    // The payment is a real expense: the funding account loses the money and
    // the expense shows up in the movements list.
    await page.goto('/money_sources/cash');
    const account = page.locator('[data-testid="account-card"]', { hasText: accountName }).first();
    await expect(account.locator('.account-balance-amount')).toHaveText('$4.000.000');

    await page.goto('/expenses');
    await expect(page.locator('#expenseTable', { hasText: 'Abono extraordinario' })).toBeVisible();
  });

  test('a credit card extra payment frees part of the credit limit', async ({ page }) => {
    const accountName = `Cuenta Pago TDC-${Date.now()}`;
    const cardName = `TDC Abono-${Date.now()}`;
    const purchase = `Compra TDC ${Date.now()}`;

    await createMoneySource(page, accountName, 'account', {
      startingBalance: '2000000',
      // A transfer into a card charges the 4x1.000 on the funding account;
      // exempt it so the assertion checks the abono alone.
      fill: async (page) => {
        await page.locator('[data-kind-panel~="account"] #money_source_gmf_exempt').check();
      }
    });
    await createCreditCard(page, cardName, { creditLimit: '5000000' });

    const cardPath = await showPath(page, 'credit-card-card', cardName);
    const cardId = cardPath.split('/').pop();
    await createExpenseChargedTo(page, { amount: '300000', description: purchase, moneySourceId: cardId });

    await page.goto(cardPath);
    await page.locator('[data-tab-slug="abonos"]').click();

    await page.locator('select[name="funding_money_source_id"]').selectOption({ label: accountName });
    await page.locator('input[name="extra_amount"]').fill('100000');
    await page.getByRole('button', { name: 'Aplicar abono' }).click();

    await expect(page).toHaveURL(new RegExp(`${cardPath}$`));
    await expect(page.getByText('Abono aplicado al saldo del crédito. La proyección se actualizará.')).toBeVisible();

    const debtPanel = page.locator('.card-debt');
    await expect(debtPanel.locator('.col-4').filter({ hasText: 'Usado' }).locator('.fs-5')).toHaveText('$200.000');
    await expect(debtPanel.locator('.col-4').filter({ hasText: 'Disponible' }).locator('.fs-5')).toHaveText('$4.800.000');

    await page.locator('[data-tab-slug="abonos"]').click();
    const abonos = page.locator('#source-tab-abonos');
    await expect(abonos.getByText('-$100.000').first()).toBeVisible();

    // The funding account paid the abono.
    await page.goto('/money_sources/cash');
    const account = page.locator('[data-testid="account-card"]', { hasText: accountName }).first();
    await expect(account.locator('.account-balance-amount')).toHaveText('$1.900.000');
  });
});
