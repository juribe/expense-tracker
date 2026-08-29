const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('dashboard is working', () => {
  test('user can view dashboard summary', async ({ page }) => {
    await signUp(page);
    const response = await page.goto('/dashboard');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Saldo neto' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Gastos de este mes' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Distribución por categoría' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Gastos recientes' })).toBeVisible();
  });

  test('user can add an expense from the dashboard', async ({ page }) => {
    await signUp(page);
    const category = `Food-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/dashboard');
    await page.locator('#expense_amount').fill('50.00');
    await page.locator('#expense_category_id').selectOption({ label: category });
    await page.locator('#expense_description').fill('Grocery Store');
    await page.getByRole('button', { name: 'Agregar Gasto' }).click();

    await expect(page.getByText('El gasto se creó correctamente.')).toBeVisible();
    await page.goto('/dashboard');
    await expect(page.getByText('Grocery Store')).toBeVisible();
    await expect(page.getByText('$50').first()).toBeVisible();
  });

  test('user can navigate to add new expense', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');
    await page.getByRole('link', { name: /Agregar Gasto/ }).click();
    await expect(page).toHaveURL(/\/expenses\/new/);
    await expect(page.locator('form')).toBeVisible();
  });
});
