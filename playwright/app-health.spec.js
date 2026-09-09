const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('app health checks', () => {
  test('health endpoint responds successfully', async ({ page }) => {
    const response = await page.goto('/up');
    expect(response.ok()).toBeTruthy();
  });

  test('unauthenticated user is redirected to sign in', async ({ page }) => {
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/sign_in/);
  });

  test('user can sign up and access dashboard', async ({ page }) => {
    await signUp(page);
    const response = await page.goto('/dashboard');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Saldo neto' })).toBeVisible();
  });

  test('dashboard displays summary sections', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');
    await expect(page.getByRole('heading', { name: 'Gastos de este mes' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Distribución por categoría' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Gastos recientes' })).toBeVisible();
  });

  test('expenses CRUD flow works end-to-end', async ({ page }) => {
    await signUp(page);
    const category = `Food-${Date.now()}`;
    await createCategory(page, category);

    // Create expense
    await page.goto('/dashboard');
    await page.locator('#expense_amount').fill('75');
    await page.locator('#expense_category_id').selectOption({ label: category });
    await page.locator('#expense_description').fill('Grocery Store');
    await page.getByRole('button', { name: 'Agregar Gasto' }).click();
    await expect(page.getByText('El gasto se creó correctamente.')).toBeVisible();

    // Verify on dashboard
    await page.goto('/dashboard');
    await expect(page.getByText('Grocery Store')).toBeVisible();
    await expect(page.getByText('$75').first()).toBeVisible();

    // Navigate to expenses index
    await page.goto('/expenses');
    await expect(page.getByText('Grocery Store').first()).toBeVisible();
  });
});
