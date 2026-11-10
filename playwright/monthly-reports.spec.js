const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

async function addExpense(page, { amount, date, description, source }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(amount);
  await page.locator('#expense_date').fill(date);
  await page.locator('#expense_description').fill(description);
  await page.locator('#expense_money_source_id').selectOption({ label: source });
  await page.getByRole('button', { name: 'Guardar' }).click();
}

async function openJanuary2023(page) {
  await page.goto('/monthly_reports');
  await Promise.all([
    page.waitForURL(/period=custom/),
    page.locator('#report-period-select').selectOption('custom'),
  ]);
  await page.locator('#start_date').fill('01/01/2023');
  await page.locator('#end_date').fill('31/01/2023');
  await Promise.all([
    page.waitForURL(/start_date=2023-01-01/),
    page.getByRole('button', { name: 'Aplicar' }).click(),
  ]);
}

test.describe('monthly reports are working', () => {
  test('user can view the cycle balance with no data', async ({ page }) => {
    await signUp(page);
    const response = await page.goto('/monthly_reports');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Balance del ciclo' })).toBeVisible();
    await expect(page.getByText('Cuando registres ingresos y gastos, aquí podrás consultar el balance de tus ciclos.')).toBeVisible();
  });

  test('user can view a cycle report after adding an expense', async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);

    await addExpense(page, { amount: '1250', date: '15/01/2023', description: 'January rent', source: efectivo });
    await openJanuary2023(page);

    await expect(page.getByText('Enero 2023')).toBeVisible();
    await expect(page.getByText('$1.250').first()).toBeVisible();

    await page.getByRole('link', { name: 'Ver detalles' }).click();
    await expect(page).toHaveURL(/\/monthly_reports\/2023-01/);
    await expect(page.getByRole('heading', { name: 'Balance del ciclo' })).toBeVisible();
    await expect(page.getByText('January rent')).toBeVisible();
  });

  test('cycle transactions can be sorted by amount', async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);

    await addExpense(page, { amount: '1250', date: '04/01/2023', description: 'January rent', source: efectivo });
    await addExpense(page, { amount: '500', date: '05/01/2023', description: 'Coffee', source: efectivo });
    await openJanuary2023(page);

    await page.getByRole('link', { name: 'Ver detalles' }).click();
    const rows = page.locator('[data-testid=monthly-balance-transactions-table] tbody tr');
    await expect(rows).toHaveCount(2);

    const amountHeader = page.getByRole('button', { name: 'Valor' });
    await amountHeader.click();
    await expect(rows.first()).toContainText('January rent');
    await amountHeader.click();
    await expect(rows.first()).toContainText('Coffee');
  });
});
