const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('expense pages are working', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);
  });

  test('user can create a new expense', async ({ page }) => {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('45.20');
    await page.locator('#expense_date').fill('2023-11-15');
    await page.locator('#expense_description').fill('Grocery shopping');
    await page.getByRole('button', { name: /Create Expense/ }).click();

    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText('Expense was successfully created.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Grocery shopping');
  });

  test('user can view expense index', async ({ page }) => {
    const response = await page.goto('/expenses');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('h1')).toContainText('Expenses');
    await expect(page.getByRole('link', { name: /Add Expense/ }).first()).toBeVisible();
  });

  test('user can update an expense', async ({ page }) => {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('15.50');
    await page.locator('#expense_date').fill('2023-10-25');
    await page.locator('#expense_description').fill('Lunch at cafe');
    await page.getByRole('button', { name: /Create Expense/ }).click();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Lunch at cafe');

    await page.getByRole('link', { name: /Edit Lunch at cafe/ }).first().click();
    await page.locator('#expense_description').fill('Dinner at restaurant');
    await page.locator('#expense_amount').fill('25.00');
    await page.getByRole('button', { name: /Update Expense/ }).click();

    await expect(page.getByText('Expense was successfully updated.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Dinner at restaurant');
  });

  test('user can delete an expense', async ({ page }) => {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('15.50');
    await page.locator('#expense_date').fill('2023-10-25');
    await page.locator('#expense_description').fill('Lunch at cafe');
    await page.getByRole('button', { name: /Create Expense/ }).click();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Lunch at cafe');

    await page.getByRole('button', { name: /Delete Lunch at cafe/ }).first().click();
    await page.locator('#confirmDelete').click();

    await expect(page.getByText('Expense was successfully deleted.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveCount(0);
  });
});
