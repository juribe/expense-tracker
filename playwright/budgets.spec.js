const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');
const { createMoneySource } = require('./helpers/money_sources');

async function createBudget(page, categoryName, amount) {
  await page.goto('/budgets/new');
  await pickCategory(page, 'budget_category_id', categoryName);
  await page.locator('#budget_monthly_amount').fill(String(amount));
  await page.getByRole('button', { name: 'Crear Presupuesto' }).click();
  await expect(page).toHaveURL(/\/budgets$/);
  await expect(page.getByText('El presupuesto se creó correctamente.')).toBeVisible();
}

async function createExpense(page, { amount, category, description, date, source }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(String(amount));
  if (date) {
    await page.locator('#expense_date').fill(date);
  }
  await pickCategory(page, 'expense_category_id', category);
  if (description) {
    await page.locator('#expense_description').fill(description);
  }
  await page.locator('#expense_money_source_id').selectOption({ label: source });
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).not.toHaveURL(/\/expenses\/new$/);
}

async function createAccount(page, name, balance) {
  await page.goto('/money_sources/new');
  await page.locator('#money_source_name').fill(name);
  await page.locator('#money_source_kind').selectOption('account');
  await page.locator('[data-kind-panel~="account"] #money_source_starting_balance').fill(String(balance));
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
  return `${String(last.getDate()).padStart(2, '0')}/${String(last.getMonth() + 1).padStart(2, '0')}/${last.getFullYear()}`;
}

function previousMonthParam() {
  const now = new Date();
  const date = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

test.describe('category budgets are working', () => {
  test('user can create a budget and see it on the budgets page', async ({ page }) => {
    await signUp(page);
    const category = `Food-${Date.now()}`;
    await createCategory(page, category);

    await page.goto('/budgets');
    await expect(page.getByText('Aún no tienes presupuestos')).toBeVisible();

    await createBudget(page, category, 800000);

    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card).toBeVisible();
    await expect(card.locator('[data-testid="budget-budget-amount"]')).toHaveText('$800.000');
  });

  test('user can edit a budget', async ({ page }) => {
    await signUp(page);
    const category = `Transport-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 500000);

    await page.locator(`a[aria-label="Editar presupuesto de ${category}"]`).click();
    await expect(page).toHaveURL(/\/budgets\/[0-9a-f-]{36}\/edit/);

    await page.locator('#budget_monthly_amount').fill('1000000');
    await page.getByRole('button', { name: 'Actualizar Presupuesto' }).click();

    await expect(page).toHaveURL(/\/budgets$/);
    await expect(page.getByText('El presupuesto se actualizó correctamente.')).toBeVisible();

    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card.locator('[data-testid="budget-budget-amount"]')).toHaveText('$1.000.000');
  });

  test('user can delete a budget', async ({ page }) => {
    await signUp(page);
    const category = `Fun-${Date.now()}`;
    await createCategory(page, category);
    await createBudget(page, category, 100000);

    await page.locator(`button[aria-label="Eliminar presupuesto de ${category}"]`).click();
    await page.locator('[data-testid="dialog-accept"]').click();

    await expect(page.getByText('El presupuesto se eliminó correctamente.')).toBeVisible();
    await expect(page.getByText(category)).toHaveCount(0);
  });

  test('budget card shows spent, remaining, percentage and attention status', async ({ page }) => {
    await signUp(page);
    const category = `Restaurants-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 800000);
    await createExpense(page, { amount: 620000, category, description: 'Dinner', source: efectivo });

    await page.goto('/budgets');
    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card.getByText('Gastado')).toBeVisible();
    await expect(card.locator('[data-testid="budget-spent-amount"]')).toHaveText('$620.000');
    await expect(card.getByText('Disponible')).toBeVisible();
    await expect(card.locator('[data-testid="budget-available-amount"]')).toHaveText('$180.000');
    await expect(card.locator('[data-testid="budget-usage"]')).toHaveText('78%');
    await expect(card.locator('[data-testid="budget-status"]')).toContainText('Atención');
  });

  test('budget reaches near-limit state at 90% or more', async ({ page }) => {
    await signUp(page);
    const category = `Shopping-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 100000);
    await createExpense(page, { amount: 90000, category, description: 'Clothes', source: efectivo });

    await page.goto('/budgets');
    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card.locator('[data-testid="budget-usage"]')).toHaveText('90%');
    await expect(card.locator('[data-testid="budget-status"]')).toContainText('Cerca del límite');
    await expect(card.locator('[data-testid="budget-available-amount"]')).toHaveText('$10.000');
  });

  test('budget shows over-budget state when spending exceeds the amount', async ({ page }) => {
    await signUp(page);
    const category = `Overspend-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 500000);
    await createExpense(page, { amount: 620000, category, description: 'Big purchase', source: efectivo });

    await page.goto('/budgets');
    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card.locator('[data-testid="budget-available-amount"]')).toHaveText('-$120.000');
    await expect(card.locator('[data-testid="budget-exceeded-hint"]')).toContainText('Superado por $120.000');
    await expect(card.locator('[data-testid="budget-status"]')).toContainText('Presupuesto superado');
  });

  test('budget spent excludes transfers', async ({ page }) => {
    await signUp(page);
    const category = `TransferCheck-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 100000);

    const savingsName = `Savings-${Date.now()}`;
    const checkingName = `Checking-${Date.now()}`;
    await createAccount(page, savingsName, 100000);
    await createAccount(page, checkingName, 0);

    // Transfers are quick actions: the origin account card's menu opens the
    // compact modal with the origin fixed, so the form only asks for the
    // destination and the amount.
    await page.goto('/money_sources/cash');
    const savingsCard = page.locator('[data-testid="account-card"]', { hasText: savingsName });
    await savingsCard.locator('[data-testid="card-actions-toggle"]').click();
    await savingsCard.locator('[data-testid="quick-action-transfer"]').click();
    const quickForm = page.locator('[data-testid="quick-transfer-form"]');
    await expect(quickForm).toBeVisible();
    await quickForm.locator('#transfer_amount').fill('30000');
    await quickForm.locator('#transfer_to_source_id').selectOption({ label: checkingName });
    await quickForm.getByRole('button', { name: 'Crear Transferencia' }).click();
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();

    await createExpense(page, { amount: 40000, category, description: 'Food', source: efectivo });

    await page.goto('/budgets');
    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card.getByText('Gastado')).toBeVisible();
    await expect(card.locator('[data-testid="budget-spent-amount"]')).toHaveText('$40.000');
  });

  test('budget uses the correct month for spending', async ({ page }) => {
    await signUp(page);
    const category = `MonthCheck-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 100000);
    await createExpense(page, { amount: 40000, category, description: 'Last month', date: previousMonthDate(), source: efectivo });

    await page.goto('/budgets');
    const card = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(card.getByText('Gastado')).toBeVisible();
    await expect(card.locator('[data-testid="budget-spent-amount"]')).toHaveText('$0');

    await page.goto(`/budgets?month=${previousMonthParam()}`);
    const prevCard = page.locator('[data-testid="budget-card"]', { hasText: category });
    await expect(prevCard.locator('[data-testid="budget-spent-amount"]')).toHaveText('$40.000');
  });

  test('dashboard shows the cycle budget summary', async ({ page }) => {
    await signUp(page);
    const category = `Dash-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 100000);
    await createExpense(page, { amount: 90000, category, description: 'Lunch', source: efectivo });

    await page.goto('/dashboard');
    const section = page.getByTestId('dashboard-budget');
    await expect(section.getByText('Presupuesto del ciclo')).toBeVisible();
    await expect(section.locator('.dash-budget-value')).toContainText('$90.000');
    await expect(section.locator('.dash-budget-value')).toContainText('de $100.000');
    await expect(section.locator('.dash-budget-progress')).toHaveAttribute('aria-valuenow', '90');
    await expect(section.locator('.dash-budget-foot')).toContainText('90% utilizado');
    await expect(section.locator('.dash-budget-foot')).toContainText('$10.000 disponibles');
  });

  test('budget report total row aligns with the amount columns', async ({ page }) => {
    await signUp(page);
    const category = `ReportAlign-${Date.now()}`;
    await createCategory(page, category);
    const efectivo = await createMoneySource(page, `Efectivo-${Date.now()}`);
    await createBudget(page, category, 1000000);
    await createExpense(page, { amount: 250000, category, description: 'Report alignment', source: efectivo });

    await page.goto('/reports/budgets');

    const bodyAlignment = await page.locator('.budget-table tbody tr').first().locator('td')
      .evaluateAll(cells => cells.map(cell => getComputedStyle(cell).textAlign));
    const totalAlignment = await page.locator('.budget-table tfoot tr').locator('td')
      .evaluateAll(cells => cells.map(cell => getComputedStyle(cell).textAlign));

    expect(bodyAlignment.slice(1)).toEqual(['right', 'right', 'right', 'right']);
    expect(totalAlignment.slice(1)).toEqual(['right', 'right', 'right', 'right']);
  });
});