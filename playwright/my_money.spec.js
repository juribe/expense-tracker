const { test, expect } = require('@playwright/test');
const { signUp, createCategory, createIncomeCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');

test.describe('my money in simple mode', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page, { moneyTrackingMode: 'simple' });
  });

  test('reuses the money source detail without advanced actions', async ({ page }) => {
    const expenseCategory = `Mi dinero gasto-${Date.now()}`;
    const incomeCategory = `Mi dinero ingreso-${Date.now()}`;
    const expenseDescription = `Almuerzo Mi dinero ${Date.now()}`;
    const incomeDescription = `Ingreso Mi dinero ${Date.now()}`;

    await createCategory(page, expenseCategory);
    await createIncomeCategory(page, incomeCategory);

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('30000');
    await page.locator('#expense_description').fill(expenseDescription);
    await pickCategory(page, 'expense_category_id', expenseCategory);
    await page.getByRole('button', { name: 'Guardar' }).click();

    await page.goto('/incomes/new');
    await page.locator('#income_amount').fill('100000');
    await page.locator('#income_description').fill(incomeDescription);
    await pickCategory(page, 'income_category_id', incomeCategory);
    await page.getByRole('button', { name: 'Crear Ingreso' }).click();

    await page.goto('/mi_dinero');

    await expect(page).toHaveURL(/\/mi_dinero$/);
    await expect(page.getByRole('heading', { name: 'Mi dinero', exact: true })).toBeVisible();
    await expect(page.getByText('Saldo registrado', { exact: true })).toBeVisible();
    await expect(page.getByTestId('my-money-period-summary')).toBeVisible();
    await expect(page.getByText('Ingresos del período')).toBeVisible();
    await expect(page.getByText('Gastos del período')).toBeVisible();
    await expect(page.getByText('Balance del período')).toBeVisible();

    await expect(page.getByRole('link', { name: /Transferir|Depositar|Retirar|Editar/ })).toHaveCount(0);
    await expect(page.getByText('Fuente relacionada')).toHaveCount(0);
    await expect(page.getByText('Money Source')).toHaveCount(0);

    await page.getByRole('link', { name: 'Ver movimientos' }).click();
    await expect(page.locator('#movementRows').getByText(expenseDescription)).toBeVisible();
    await expect(page.locator('#movementRows').getByText(incomeDescription)).toBeVisible();
    await expect(page.locator('#movementRows').getByText('Gasto').first()).toBeVisible();
    await expect(page.locator('#movementRows').getByText('Ingreso').first()).toBeVisible();
  });

  test('keeps the statement filters available', async ({ page }) => {
    const incomeCategory = `Filtro ingreso-${Date.now()}`;
    const incomeDescription = `Ingreso filtro ${Date.now()}`;
    const expenseCategory = `Filtro gasto-${Date.now()}`;
    const expenseDescription = `Gasto filtro ${Date.now()}`;

    await createIncomeCategory(page, incomeCategory);
    await createCategory(page, expenseCategory);

    await page.goto('/incomes/new');
    await page.locator('#income_amount').fill('50000');
    await page.locator('#income_description').fill(incomeDescription);
    await pickCategory(page, 'income_category_id', incomeCategory);
    await page.getByRole('button', { name: 'Crear Ingreso' }).click();

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('20000');
    await page.locator('#expense_description').fill(expenseDescription);
    await pickCategory(page, 'expense_category_id', expenseCategory);
    await page.getByRole('button', { name: 'Guardar' }).click();

    await page.goto('/mi_dinero?kind=in');
    await page.getByRole('link', { name: 'Ver movimientos' }).click();

    await expect(page.locator('#movementRows').getByText(incomeDescription)).toBeVisible();
    await expect(page.locator('#movementRows').getByText(expenseDescription)).toHaveCount(0);
  });

  test('does not expose money source navigation in simple mode', async ({ page }) => {
    await page.goto('/dashboard');

    await expect(page.getByTestId('nav-my-money')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Efectivo y Cuentas' })).toHaveCount(0);
    await expect(page.getByRole('link', { name: 'Tarjetas de Crédito' })).toHaveCount(0);
    await expect(page.getByRole('link', { name: 'Transferencias' })).toHaveCount(0);
  });
});
