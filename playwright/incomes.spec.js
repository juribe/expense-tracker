const { test, expect } = require('@playwright/test');
const { signUp, createIncomeCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');
const { createMoneySource } = require('./helpers/money_sources');

// Flatpickr upgrades every date input: the visible field (#income_date) uses
// dd/MM/yyyy and the hidden original keeps the ISO value the server parses.
function todayInput() {
  const now = new Date();
  const pad = (value) => String(value).padStart(2, '0');
  return `${pad(now.getDate())}/${pad(now.getMonth() + 1)}/${now.getFullYear()}`;
}

async function createMonthlyIncome(page, { description, amount, paymentDay, category }) {
  await page.goto('/monthly_incomes');
  await page.getByTestId('add-recurring').click();
  await expect(page.getByTestId('form-modal')).toBeVisible();

  await pickCategory(page, 'recurring_template_category_id', category);
  await page.locator('#recurring_template_description').fill(description);
  await page.locator('#recurring_template_amount').fill(String(amount));
  await page.locator('#recurring_template_payment_day').fill(String(paymentDay));
  await page.getByTestId('save-recurring').click();

  await expect(page.getByTestId('recurring-row').filter({ hasText: description })).toBeVisible();
}

test.describe('incomes', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can create an income and see it listed', async ({ page }) => {
    const categoryName = `Salario-${Date.now()}`;
    const sourceName = `Cuenta Ingresos-${Date.now()}`;
    const description = `Nómina ${Date.now()}`;

    await createIncomeCategory(page, categoryName);
    await createMoneySource(page, sourceName, 'account', { startingBalance: '0' });

    await page.goto('/incomes/new');
    await page.locator('#income_amount').fill('3500000');
    await page.locator('#income_date').fill(todayInput());
    await page.locator('#income_description').fill(description);
    await pickCategory(page, 'income_category_id', categoryName);
    await page.locator('#income_money_source_id').selectOption({ label: sourceName });
    await page.getByRole('button', { name: 'Crear Ingreso' }).click();

    await expect(page).toHaveURL(/\/incomes$/);
    await expect(page.getByText('Ingreso creado exitosamente.')).toBeVisible();

    const row = page.locator('[data-testid="row"]', { hasText: description });
    await expect(row).toBeVisible();
    await expect(row).toContainText('$3.500.000');
    await expect(row).toContainText(categoryName);
    await expect(page.getByTestId('summary-total')).toHaveText('$3.500.000');
    await expect(page.getByTestId('summary-count')).toHaveText('1');

    // The money landed in the selected account.
    await page.goto('/money_sources/cash');
    const card = page.locator('[data-testid="account-card"]', { hasText: sourceName }).first();
    await expect(card.locator('.account-balance-amount')).toHaveText('$3.500.000');
  });

  test('user can create a monthly income template', async ({ page }) => {
    const categoryName = `Freelance-${Date.now()}`;
    const description = `Proyecto mensual ${Date.now()}`;

    await createIncomeCategory(page, categoryName);
    await createMonthlyIncome(page, {
      description,
      amount: '4000000',
      paymentDay: 15,
      category: categoryName
    });

    const row = page.getByTestId('recurring-row').filter({ hasText: description });
    await expect(row).toContainText('$4.000.000');
    await expect(row).toContainText('Día 15');
    await expect(page.getByTestId('summary-monthly-expected')).toContainText('$4.000.000');
  });

  test('receiving a monthly income records a real income', async ({ page }) => {
    const categoryName = `Sueldo-${Date.now()}`;
    const sourceName = `Cuenta Sueldo-${Date.now()}`;
    const description = `Sueldo mensual ${Date.now()}`;

    await createIncomeCategory(page, categoryName);
    await createMoneySource(page, sourceName, 'cash', { startingBalance: '0' });
    await createMonthlyIncome(page, {
      description,
      amount: '4000000',
      paymentDay: 15,
      category: categoryName
    });

    const row = page.getByTestId('recurring-row').filter({ hasText: description });
    await row.getByTestId('process').click();

    await expect(page.getByTestId('process-modal')).toBeVisible();
    await page.locator('#processMoneySource').selectOption({ label: sourceName });
    await page.locator('#processAmount').fill('4000000');
    await page.getByTestId('confirm-process').click();

    await expect(page).toHaveURL(/\/monthly_incomes/);
    await expect(page.getByText(/Recibido .* el /)).toBeVisible();
    await expect(page.getByTestId('recurring-row').filter({ hasText: description }))
      .toContainText('Recibido');

    await page.goto('/incomes');
    const incomeRow = page.locator('[data-testid="row"]', { hasText: description });
    await expect(incomeRow).toBeVisible();
    await expect(incomeRow).toContainText('$4.000.000');

    await page.goto('/money_sources/cash');
    const card = page.locator('[data-testid="account-card"]', { hasText: sourceName }).first();
    await expect(card.locator('.account-balance-amount')).toHaveText('$4.000.000');
  });
});
