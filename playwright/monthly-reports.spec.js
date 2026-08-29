const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('monthly reports are working', () => {
  test('user can view monthly reports with no data', async ({ page }) => {
    await signUp(page);
    const response = await page.goto('/monthly_reports');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Balance mensual' })).toBeVisible();
    await expect(page.getByText('Aún no hay transacciones registradas.')).toBeVisible();
  });

  test('user can view a monthly report after adding an expense', async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('1250.00');
    await page.locator('#expense_date').fill('2023-01-15');
    await page.locator('#expense_description').fill('January rent');
    await page.getByRole('button', { name: 'Guardar' }).click();

    await page.goto('/monthly_reports');
    await expect(page.getByText('2023-01')).toBeVisible();
    await expect(page.getByText('-$1.250').first()).toBeVisible();

    await page.getByRole('link', { name: 'Ver detalles' }).click();
    await expect(page).toHaveURL(/\/monthly_reports\/2023-01/);
    await expect(page.getByRole('heading', { name: 'Balance mensual: 2023-01' })).toBeVisible();
    await expect(page.getByText('January rent')).toBeVisible();
  });
});
