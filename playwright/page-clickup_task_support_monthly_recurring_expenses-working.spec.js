const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

async function createMonthlyExpense(page, { category, description, amount, day }) {
  await page.goto('/monthly_expenses/new');
  await page.locator('#monthly_expense_category_id').selectOption({ label: category });
  await page.locator('#monthly_expense_description').fill(description);
  await page.locator('#monthly_expense_amount').fill(amount);
  await page.locator('#monthly_expense_payment_day').fill(String(day));
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page).toHaveURL(/\/monthly_expenses$/);
}

test.describe("ClickUp Task: Support Monthly Recurring Expenses", () => {
  test("/monthly_expenses pages are working", async ({ page }) => {
    await signUp(page);
    for (const path of ['/monthly_expenses', '/monthly_expenses/new']) {
      const response = await page.goto(path);
      expect(response && response.ok()).toBeTruthy();
      await expect(page.locator('body')).toBeVisible();
    }
  });

  test("user can create, pay, edit and delete a monthly expense", async ({ page }) => {
    await signUp(page);
    const category = `Car-${Date.now()}`;
    await createCategory(page, category);

    // Empty state before any configuration exists
    await page.goto('/monthly_expenses');
    await expect(page.getByText('No recurring expenses yet')).toBeVisible();

    // Create a monthly recurring expense
    await createMonthlyExpense(page, {
      category, description: 'Car Loan', amount: '2817.60', day: 15
    });
    const row = page.locator('tr[data-testid=row]');
    await expect(row).toHaveCount(1);
    await expect(row.locator('[data-testid=status] .badge')).toHaveText('Pending');
    await expect(page.getByText('$2,817.60')).toBeVisible();

    // Pay it via the confirmation modal (date defaults to configured day)
    await row.locator('[data-pay]').click();
    await expect(page.locator('#payModal')).toBeVisible();
    await expect(page.locator('#payAmount')).toHaveValue('2817.6');
    await page.locator('#payPaymentDate').fill('2026-08-15');
    await page.getByRole('button', { name: 'Confirm Payment' }).click();

    // Status flips to Paid and the Pay action disappears
    await expect(page.locator('tr[data-testid=row] [data-testid=status] .badge')).toHaveText('Paid');
    await expect(page.locator('[data-pay]')).toHaveCount(0);

    // A regular one-time expense was created with the payment date
    await page.goto('/expenses');
    await expect(page.getByRole('cell', { name: 'Car Loan', exact: true })).toBeVisible();
    await expect(page.getByText('$2,817.60').first()).toBeVisible();

    // Duplicate payment for the same month is rejected
    await page.goto('/monthly_expenses');
    await expect(page.locator('[data-pay]')).toHaveCount(0);

    // Edit the configuration
    await page.locator('a[aria-label^="Edit"]').click();
    await expect(page).toHaveURL(/\/edit$/);
    await page.locator('#monthly_expense_amount').fill('3000.00');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page).toHaveURL(/\/monthly_expenses$/);
    await expect(page.getByText('$3,000.00')).toBeVisible();

    // Delete the configuration via the confirmation modal
    await page.locator('button[aria-label^="Delete"]').click();
    await expect(page.locator('#deleteModal')).toBeVisible();
    await page.locator('#confirmDelete').click();
    await expect(page.getByText('No recurring expenses yet')).toBeVisible();
  });
});
