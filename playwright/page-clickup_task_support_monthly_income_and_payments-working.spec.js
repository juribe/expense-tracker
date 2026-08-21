const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('ClickUp Task: Support Monthly Income and Payments', () => {
  let categoryName;

  test.beforeEach(async ({ page }) => {
    await signUp(page);
    categoryName = `Salary-${Date.now()}`;
    await createCategory(page, categoryName);
  });

  async function openRecurringPage(page, type = 'income') {
    await page.goto(`/recurring_transactions?type=${type}`);
    await expect(page.getByTestId('recurring-page')).toBeVisible();
  }

  async function createRecurring(page, { description, amount, day }) {
    await page.getByTestId('add-recurring').click();
    const modal = page.locator('#recurringFormModal');
    await expect(modal).toBeVisible();
    await modal.locator('#recurring_transaction_category_id').selectOption({ label: categoryName });
    await modal.locator('#recurring_transaction_description').fill(description);
    await modal.locator('#recurring_transaction_amount').fill(amount);
    await modal.locator('#recurring_transaction_payment_day').fill(day);
    await page.getByTestId('save-recurring').click();
    await expect(page.getByText(/was successfully created/)).toBeVisible();
  }

  test('recurring transactions page renders with income and expense tabs', async ({ page }) => {
    const response = await page.goto('/recurring_transactions');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.getByTestId('recurring-page')).toBeVisible();
    await expect(page.locator('.nav-tabs')).toContainText('Income');
    await expect(page.locator('.nav-tabs')).toContainText('Expense');
    await expect(page.getByTestId('empty-state')).toBeVisible();
  });

  test('user can create a recurring monthly income and see it pending', async ({ page }) => {
    await openRecurringPage(page);
    await createRecurring(page, { description: 'Freelance Job', amount: '6500', day: '15' });

    const row = page.getByTestId('recurring-row');
    await expect(row).toHaveCount(1);
    await expect(row).toContainText(categoryName);
    await expect(row).toContainText('Freelance Job');
    await expect(row).toContainText('$6,500.00');
    await expect(row.getByTestId('status')).toContainText('Pending');

    const receive = row.getByTestId('process');
    await expect(receive).toContainText('Receive');
    await expect(receive).toBeEnabled();
  });

  test('user can create a recurring monthly payment and see a Pay button', async ({ page }) => {
    await openRecurringPage(page, 'expense');
    await createRecurring(page, { description: 'Car Loan', amount: '2817.60', day: '15' });

    const row = page.getByTestId('recurring-row');
    await expect(row).toHaveCount(1);
    await expect(row).toContainText('Car Loan');
    await expect(row.getByTestId('status')).toContainText('Pending');
    await expect(row.getByTestId('process')).toContainText('Pay');
  });

  test('Receive creates a one-time income and marks the month completed', async ({ page }) => {
    await openRecurringPage(page);
    await createRecurring(page, { description: 'Freelance Job', amount: '6500', day: '15' });

    const row = page.getByTestId('recurring-row');
    await row.getByTestId('process').click();

    const modal = page.getByTestId('process-modal');
    await expect(modal).toBeVisible();
    await expect(modal).toContainText('Confirm Receive');
    await expect(modal).toContainText(categoryName);
    await expect(modal).toContainText('Freelance Job');
    await expect(modal).toContainText('$6,500.00');

    // Amount defaults to the configured value but can be modified.
    await expect(modal.locator('#processAmount')).toHaveValue('6500.00');
    await modal.locator('#processAmount').fill('6800');
    await modal.locator('#processDate').fill('2026-08-18');
    await page.getByTestId('confirm-process').click();

    await expect(page.getByText(/Received \$6,800\.00 on August 18, 2026\./)).toBeVisible();
    await expect(row.getByTestId('status')).toContainText('Completed');
    await expect(row.getByTestId('process-disabled')).toBeVisible();
    await expect(row.getByTestId('process-disabled')).toContainText('Receive');
    await expect(row).toContainText('August 18, 2026'); // Last received column

    // Recurring configuration remains active for future months.
    await expect(row).toHaveAttribute('data-active', 'true');
  });

  test('Pay creates a one-time expense from the recurring configuration', async ({ page }) => {
    await openRecurringPage(page, 'expense');
    await createRecurring(page, { description: 'Car Loan', amount: '2817.60', day: '15' });

    const row = page.getByTestId('recurring-row');
    await row.getByTestId('process').click();

    const modal = page.getByTestId('process-modal');
    await expect(modal).toBeVisible();
    await expect(modal).toContainText('Confirm Pay');
    await modal.locator('#processDate').fill('2026-08-15');
    await page.getByTestId('confirm-process').click();

    await expect(page.getByText(/Paid \$2,817\.60 on August 15, 2026\./)).toBeVisible();
    await expect(row.getByTestId('status')).toContainText('Completed');
  });

  test('user can edit a recurring transaction from the table', async ({ page }) => {
    await openRecurringPage(page);
    await createRecurring(page, { description: 'Freelance Job', amount: '6500', day: '15' });

    const row = page.getByTestId('recurring-row');
    await row.getByTestId('edit').click();

    const modal = page.locator('#recurringFormModal');
    await expect(modal).toBeVisible();
    await expect(modal).toContainText('Edit Recurring Transaction');
    await expect(modal.locator('#recurring_transaction_description')).toHaveValue('Freelance Job');
    await modal.locator('#recurring_transaction_amount').fill('7000');
    await page.getByTestId('save-recurring').click();

    await expect(page.getByText(/was successfully updated/)).toBeVisible();
    await expect(row).toContainText('$7,000.00');
  });

  test('user can deactivate and delete a recurring transaction', async ({ page }) => {
    await openRecurringPage(page);
    await createRecurring(page, { description: 'Rental Income', amount: '1200', day: '5' });
    const row = page.getByTestId('recurring-row');

    // Deactivate flips the status badge to Inactive.
    await row.getByTestId('deactivate').click();
    await expect(page.getByText(/was successfully deactivated/)).toBeVisible();
    await expect(row.getByTestId('status')).toContainText('Inactive');

    // Reactivate.
    await row.getByTestId('deactivate').click();
    await expect(page.getByText(/was successfully activated/)).toBeVisible();
    await expect(row.getByTestId('status')).toContainText('Pending');

    // Delete removes the configuration after confirmation.
    await row.getByTestId('delete').click();
    await page.getByTestId('confirm-delete').click();
    await expect(page.getByText(/was successfully deleted/)).toBeVisible();
    await expect(page.getByTestId('empty-state')).toBeVisible();
  });
});
