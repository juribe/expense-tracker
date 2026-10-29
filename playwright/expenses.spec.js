const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

test.describe('expense pages are working', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);
    await createMoneySource(page, `Efectivo-${Date.now()}`);
  });

  test('user can create a new expense', async ({ page }) => {
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('45.20');
    await page.locator('#expense_date').fill('15/11/2023');
    await page.locator('#expense_description').fill('Grocery shopping');
    await page.locator('#expense_money_source_id').selectOption({ index: 1 });
    await page.getByRole('button', { name: 'Guardar' }).click();

    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText('El gasto se creó correctamente.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Grocery shopping');
  });

  test('user can view expense index', async ({ page }) => {
    const response = await page.goto('/expenses');
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('h1')).toContainText('Gastos');
    await expect(page.getByRole('link', { name: /Agregar Gasto/ }).first()).toBeVisible();
  });

  async function fillExpense(page, amount, date, description) {
    await page.locator('#expense_amount').fill(amount);
    await page.locator('#expense_date').fill(date);
    await page.locator('#expense_description').fill(description);
    await page.locator('#expense_money_source_id').selectOption({ index: 1 });
  }

  test('user can update an expense', async ({ page }) => {
    await page.goto('/expenses/new');
    await fillExpense(page, '15.50', '25/10/2023', 'Lunch at cafe');
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Lunch at cafe');

    const editRow = page.locator('#expenseTable tr', { hasText: 'Lunch at cafe' });
    await editRow.getByRole('link', { name: /Editar/i }).click();
    await page.locator('#expense_description').fill('Dinner at restaurant');
    await page.locator('#expense_amount').fill('25.00');
    await page.getByRole('button', { name: 'Guardar' }).click();

    await expect(page.getByText('El gasto se actualizó correctamente.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Dinner at restaurant');
  });

  test('user can delete an expense', async ({ page }) => {
    await page.goto('/expenses/new');
    await fillExpense(page, '15.50', '25/10/2023', 'Lunch at cafe');
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Lunch at cafe');

    const deleteRow = page.locator('#expenseTable tr', { hasText: 'Lunch at cafe' });
    await deleteRow.getByRole('button', { name: /Eliminar/i }).click();
    await page.locator('#confirmDelete').click();

    await expect(page.getByText('El gasto se eliminó correctamente.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveCount(0);
  });

  test('user can search expenses by description text', async ({ page }) => {
    for (const description of [ 'Cafe con leche', 'Bus ticket' ]) {
      await page.goto('/expenses/new');
      await fillExpense(page, '10.00', '25/10/2023', description);
      await page.getByRole('button', { name: 'Guardar' }).click();
      await expect(page.locator('#expenseTable td.desc-cell').filter({ hasText: description })).toHaveCount(1);
    }

    await page.goto('/expenses');
    await page.getByTestId('expense-search').fill('cafe');
    await page.getByRole('button', { name: 'Filtrar gastos' }).click();

    await expect(page).toHaveURL(/q=cafe/);
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveCount(1);
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Cafe con leche');

    // Removing the text chip brings the full list back.
    await page.getByTestId('chip-q').click();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveCount(2);
  });
});
