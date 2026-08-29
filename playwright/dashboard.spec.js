const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('dashboard is working', () => {
  test('user can view dashboard summary', async ({ page }) => {
    await signUp(page);
    const response = await page.goto('/dashboard');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByRole('heading', { name: 'Net Balance' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Expenses This Month' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Category Breakdown' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Recent Expenses' })).toBeVisible();
  });

  test('user can add an expense from the dashboard', async ({ page }) => {
    await signUp(page);
    const category = `Food-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/dashboard');
    await page.locator('#expense_amount').fill('50.00');
    await page.locator('#expense_category_id').selectOption({ label: category });
    await page.locator('#expense_description').fill('Grocery Store');
    await page.getByRole('button', { name: 'Add Expense' }).click();

    await expect(page.getByText('Expense was successfully created.')).toBeVisible();
    await page.goto('/dashboard');
    await expect(page.getByText('Grocery Store')).toBeVisible();
    await expect(page.getByText('$50.00').first()).toBeVisible();
  });

  test('user can navigate to add new expense', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');
    await page.getByRole('link', { name: /Add First Expense/ }).click();
    await expect(page).toHaveURL(/\/expenses\/new/);
    await expect(page.locator('form')).toBeVisible();
  });
});
