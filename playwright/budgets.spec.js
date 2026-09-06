const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

async function createBudget(page, categoryName, amount) {
  await page.goto('/budgets/new');
  await page.locator('#budget_category_id').selectOption({ label: categoryName });
  await page.locator('#budget_monthly_amount').fill(String(amount));
  await page.getByRole('button', { name: 'Crear Presupuesto' }).click();
  await expect(page).toHaveURL(/\/budgets$/);
  await expect(page.getByText('El presupuesto se creó correctamente.')).toBeVisible();
}

async function createExpense(page, { amount, category, description, date }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(String(amount));
  if (date) {
    await page.locator('#expense_date').fill(date);
  }
  await page.locator('#expense_category_id').selectOption({ label: category });
  if (description) {
    await page.locator('#expense_description').fill(description);
  }
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).not.toHaveURL(/\/expenses\/new$/);
}

async function createAccount(page, name, balance) {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption('account');
  await page.locator('#money_source_starting_balance').fill(String(balance));
  await page.locator('form input[type="submit"]').click();
  await expect(page).not.toHaveURL(/\/money_sources\/new/);
  await expect(page).not.toHaveURL(/\/money_sources$/);
  await expect(page.getByText(name)).toBeVisible();
}

function previousMonthDate() {
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth();
  const last = new Date(y, m, 0);
  return `${last.getFullYear()}-${String(last.getMonth() + 1).padStart(2, '0')}-01`;
}

test.describe('category budgets are working', () => {
  test('user can create a budget and see it on the budgets page', async ({ page }) => {
    await signUp(page);
    const category = `Food-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/budgets');
    await expect(page.getByText('Aún no tienes presupuestos')).toBeVisible();

    await createBudget(page, category, 800000);

    const card = page.locator('.card', { hasText: category });
    await expect(card).toBeVisible();
    await expect(card.locator('.budget-amount').first()).toHaveText('$800.000');
  });

  test('user can edit a budget', async ({ page }) => {
    await signUp(page);
    const category = `Transport-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 500000);

    await page.locator(`a[aria-label="Editar presupuesto de ${category}"]`).click();
    await expect(page).toHaveURL(/\/budgets\/\d+\/edit/);

    await page.locator('#budget_monthly_amount').fill('1000000');
    await page.getByRole('button', { name: 'Actualizar Presupuesto' }).click();

    await expect(page).toHaveURL(/\/budgets$/);
    await expect(page.getByText('El presupuesto se actualizó correctamente.')).toBeVisible();

    const card = page.locator('.card', { hasText: category });
    await expect(card.locator('.budget-amount').first()).toHaveText('$1.000.000');
  });

  test('user can delete a budget', async ({ page }) => {
    await signUp(page);
    const category = `Fun-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 100000);

    page.on('dialog', (dialog) => dialog.accept());
    await page.locator(`button[aria-label="Eliminar presupuesto de ${category}"]`).click();

    await expect(page.getByText('El presupuesto se eliminó correctamente.')).toBeVisible();
    await expect(page.getByText(category)).toHaveCount(0);
  });

  test('budget card shows spent, remaining, percentage and on-track status', async ({ page }) => {
    await signUp(page);
    const category = `Restaurants-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 800000);
    await createExpense(page, { amount: 620000, category, description: 'Dinner' });

    await page.goto('/budgets');
    const card = page.locator('.card', { hasText: category });
    await expect(card.getByText('Gastado')).toBeVisible();
    await expect(card.getByText('$620.000', { exact: true })).toBeVisible();
    await expect(card.getByText('Disponible')).toBeVisible();
    await expect(card.getByText('$180.000', { exact: true })).toBeVisible();
    await expect(card.getByText('78%')).toBeVisible();
    await expect(card.getByText('En camino')).toBeVisible();
  });

  test('budget reaches near-limit state at 80% or more', async ({ page }) => {
    await signUp(page);
    const category = `Shopping-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 100000);
    await createExpense(page, { amount: 85000, category, description: 'Clothes' });

    await page.goto('/budgets');
    const card = page.locator('.card', { hasText: category });
    await expect(card.getByText('85%')).toBeVisible();
    await expect(card.getByText('Cerca del límite')).toBeVisible();
    await expect(card.getByText('$15.000', { exact: true })).toBeVisible();
  });

  test('budget shows over-budget state when spending exceeds the amount', async ({ page }) => {
    await signUp(page);
    const category = `Overspend-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 500000);
    await createExpense(page, { amount: 620000, category, description: 'Big purchase' });

    await page.goto('/budgets');
    const card = page.locator('.card', { hasText: category });
    await expect(card.getByText('Excedido')).toBeVisible();
    await expect(card.getByText('$120.000', { exact: true })).toBeVisible();
    await expect(card.getByText('Superado')).toBeVisible();
  });

  test('budget spent excludes transfers', async ({ page }) => {
    await signUp(page);
    const category = `TransferCheck-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 100000);

    await createAccount(page, `Savings-${Date.now()}`, 100000);
    await createAccount(page, `Checking-${Date.now()}`, 0);

    await page.goto('/transfers/new');
    await page.locator('#transfer_amount').fill('30000');
    await page.locator('#transfer_from_source_id').selectOption({ index: 1 });
    await page.locator('#transfer_to_source_id').selectOption({ index: 2 });
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();

    await createExpense(page, { amount: 40000, category, description: 'Food' });

    await page.goto('/budgets');
    const card = page.locator('.card', { hasText: category });
    await expect(card.getByText('Gastado')).toBeVisible();
    await expect(card.getByText('$40.000', { exact: true })).toBeVisible();
  });

  test('budget uses the correct month for spending', async ({ page }) => {
    await signUp(page);
    const category = `MonthCheck-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 100000);
    await createExpense(page, { amount: 40000, category, description: 'Last month', date: previousMonthDate() });

    await page.goto('/budgets');
    const card = page.locator('.card', { hasText: category });
    await expect(card.getByText('Gastado')).toBeVisible();
    await expect(card.getByText('$0', { exact: true })).toBeVisible();

    await page.locator('a[aria-label="Mes anterior"]').click();
    await expect(page).toHaveURL(/month=/);
    const prevCard = page.locator('.card', { hasText: category });
    await expect(prevCard.getByText('$40.000', { exact: true })).toBeVisible();
  });

  test('dashboard shows a summary of budgets', async ({ page }) => {
    await signUp(page);
    const category = `Dash-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 100000);
    await createExpense(page, { amount: 90000, category, description: 'Lunch' });

    await page.goto('/dashboard');
    const section = page.locator('.card', { hasText: 'Presupuestos' });
    await expect(section.getByText('Presupuestos')).toBeVisible();
    await expect(section.getByText(category)).toBeVisible();
    await expect(section.getByText('90%')).toBeVisible();
    await expect(section.getByText(/1 presupuesto/)).toBeVisible();
  });
});