const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');
const { createMoneySource } = require('./helpers/money_sources');

async function createExpenseTemplate(page, category, { description, amount, day }) {
  await page.goto('/recurring_templates?kind=expense');
  await page.getByTestId('add-recurring').click();
  await expect(page.getByTestId('form-modal')).toBeVisible();
  await pickCategory(page, 'recurring_template_category_id', category);
  await page.locator('#recurring_template_kind').selectOption('expense');
  await page.locator('#recurring_template_description').fill(description);
  await page.locator('#recurring_template_amount').fill(amount);
  await page.locator('#recurring_template_payment_day').fill(String(day));
  await page.getByTestId('save-recurring').click();
  await expect(page.getByTestId('recurring-row').filter({ hasText: description })).toBeVisible();
}

test.describe('assign expense to recurring template', () => {
  test('shows expected amount and partial checkbox default', async ({ page }) => {
    const category = `Assign-${Date.now()}`;
    await signUp(page);
    await createCategory(page, category);
    const source = await createMoneySource(page, `Efectivo-${Date.now()}`, 'cash', { startingBalance: '1000000' });
    await createExpenseTemplate(page, category, { description: 'Internet parcial', amount: '65000', day: 5 });

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('30000');
    await pickCategory(page, 'expense_category_id', category);
    await page.locator('#expense_description').fill('Pago internet parcial');
    await page.locator('#expense_money_source_id').selectOption({ label: source });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);

    const row = page.locator('tr[data-testid="row"]', { hasText: 'Pago internet parcial' });
    await row.getByTestId('row-assign-recurring').click();
    await expect(page.locator('#bulkRecurringModal')).toBeVisible();

    await page.evaluate(() => {
      const sel = document.querySelector('#bulkRecurringSelect');
      const opt = Array.from(sel.options).find(o => o.textContent.includes('Internet parcial'));
      sel.value = opt.value;
      sel.dispatchEvent(new Event('change', { bubbles: true }));
    });

    const details = page.getByTestId('recurring-template-details');
    await expect(details).toBeVisible();
    await expect(details.locator('#recurringExpectedAmount')).toContainText('65');
    await expect(details.locator('#recurringCompleted')).not.toBeChecked();

    await page.locator('#confirmBulkRecurring').click();
    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText(/La plantilla sigue pendiente/)).toBeVisible();
  });
});
