const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

async function createExpense(page, { amount, date, description, categoryName }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(amount);
  await page.locator('#expense_date').fill(date);
  await page.locator('#expense_description').fill(description);
  await page.locator('#expense_category_id').selectOption({ label: categoryName });
  await page.getByRole('button', { name: 'Guardar' }).click();
  const row = page.locator('#expenseTable tr[data-id]', { hasText: description });
  await expect(row.locator('td.desc-cell')).toHaveText(description);
}

test.describe('expense bulk selection bar', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
    const cat = `Food-${Date.now()}`;
    await createCategory(page, cat);
    await createExpense(page, { amount: '10.00', date: '2025-01-10', description: 'Alpha expense', categoryName: cat });
    await createExpense(page, { amount: '20.00', date: '2025-01-11', description: 'Beta expense', categoryName: cat });
    await createExpense(page, { amount: '30.00', date: '2025-01-12', description: 'Gamma expense', categoryName: cat });
  });

  test('bulk bar is always visible even with nothing selected', async ({ page }) => {
    await page.goto('/expenses');
    const bulkBar = page.getByTestId('bulk-bar');
    await expect(bulkBar).toBeVisible();
    await expect(page.locator('#bulkCount')).toHaveText(/0 seleccionados/);
    await expect(page.getByTestId('bulk-category')).toBeDisabled();
    await expect(page.getByTestId('bulk-source')).toBeDisabled();
    await expect(page.locator('#bulkDelete')).toBeDisabled();
  });

  test('selection count shows the real number of selected expenses, not doubled', async ({ page }) => {
    await page.goto('/expenses');

    const desktopRows = page.locator('#expenseTable tbody tr[data-id]');
    await expect(desktopRows).toHaveCount(3);

    const firstRow = desktopRows.nth(0);
    await firstRow.locator('.row-check').check();
    await expect(page.locator('#bulkCount')).toHaveText(/\b1 seleccionados\b/);

    await desktopRows.nth(1).locator('.row-check').check();
    await expect(page.locator('#bulkCount')).toHaveText(/\b2 seleccionados\b/);
    await expect(page.locator('#bulkCount')).not.toHaveText(/4/);

    const ids = await desktopRows.evaluateAll((rows) =>
      rows.filter((r) => r.querySelector('.row-check').checked).map((r) => r.dataset.id)
    );
    expect(ids.length).toBe(2);

    await expect(page.getByTestId('bulk-category')).toBeEnabled();
    await expect(page.getByTestId('bulk-source')).toBeEnabled();
    await expect(page.locator('#bulkDelete')).toBeEnabled();
  });

  test('bulk edit modal reflects the correct number of selected expenses', async ({ page }) => {
    await page.goto('/expenses');

    const desktopRows = page.locator('#expenseTable tbody tr[data-id]');
    await desktopRows.nth(0).locator('.row-check').check();
    await desktopRows.nth(1).locator('.row-check').check();

    await page.getByTestId('bulk-category').click();
    const modal = page.getByTestId('bulk-update-modal');
    await expect(modal).toBeVisible();
    await expect(page.locator('#bulkEditTitle')).toHaveText(/2 gastos/);
    await expect(page.getByTestId('confirm-bulk-update')).toContainText('Actualizar 2 gastos');
  });
});
