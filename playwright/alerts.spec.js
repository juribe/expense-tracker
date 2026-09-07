const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

function previousMonthDate() {
  const now = new Date();
  const prev = new Date(now.getFullYear(), now.getMonth() - 1, 15);
  return `${prev.getFullYear()}-${String(prev.getMonth() + 1).padStart(2, '0')}-15`;
}

function todayDate() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

async function createExpense(page, { amount, date, category, description }) {
  await page.goto('/expenses/new');
  await page.locator('#expense_amount').fill(String(amount));
  await page.locator('#expense_date').fill(date);
  await page.locator('#expense_category_id').selectOption({ label: category });
  await page.locator('#expense_description').fill(description);
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page).toHaveURL(/\/expenses/);
}

async function enableSpendingIncreaseAlerts(page) {
  await page.goto('/settings/alerts');
  await page.getByLabel(/notablemente mayor que el mes pasado/).check();
  await page.getByRole('button', { name: 'Guardar' }).click();
  await expect(page.getByText('Preferencias guardadas')).toBeVisible();
}

test.describe('spending alerts (alertas de gasto)', () => {
  test('alerts center shows the empty state and the sidebar link', async ({ page }) => {
    await signUp(page);

    await page.goto('/alerts');
    await expect(page.getByRole('heading', { name: 'Alertas' })).toBeVisible();
    await expect(page.getByText('Estás al día')).toBeVisible();

    await expect(page.locator('.sidebar-link', { hasText: 'Alertas' })).toBeVisible();
    await expect(page.locator('.sidebar-link', { hasText: 'Alertas' }).locator('.badge')).toHaveCount(0);
  });

  test('alert settings page shows the three toggles and saves them', async ({ page }) => {
    await signUp(page);

    await page.goto('/settings/alerts');
    await expect(page.getByLabel(/80% de mi presupuesto/)).toBeChecked();
    await expect(page.getByLabel(/supere mi presupuesto/)).toBeChecked();
    await expect(page.getByLabel(/notablemente mayor que el mes pasado/)).not.toBeChecked();

    await page.getByLabel(/notablemente mayor que el mes pasado/).check();
    await page.getByRole('button', { name: 'Guardar' }).click();

    await expect(page.getByText('Preferencias guardadas')).toBeVisible();
    await expect(page.getByLabel(/notablemente mayor que el mes pasado/)).toBeChecked();
  });

  test('alerts the user when spending increases vs previous month', async ({ page }) => {
    await signUp(page);
    const category = `Transporte-${Date.now()}`;
    await createCategory(page, category);
    await enableSpendingIncreaseAlerts(page);

    await createExpense(page, { amount: 100, date: previousMonthDate(), category, description: 'Gasolina mes pasado' });
    await createExpense(page, { amount: 200, date: todayDate(), category, description: 'Gasolina este mes' });

    await page.goto('/alerts');
    await expect(page.getByText('Aumento de gasto')).toBeVisible();
    await expect(page.locator('.card', { hasText: category })).toBeVisible();
    await expect(page.locator('.sidebar-link', { hasText: 'Alertas' }).locator('.badge')).toHaveText('1');

    await page.getByRole('button', { name: 'Marcar leídas' }).click();
    await expect(page.getByText('Alertas marcadas como leídas')).toBeVisible();
    await expect(page.locator('.sidebar-link', { hasText: 'Alertas' }).locator('.badge')).toHaveCount(0);
  });

  test('filters work in the alerts center', async ({ page }) => {
    await signUp(page);
    const category = `Restaurantes-${Date.now()}`;
    await createCategory(page, category);
    await enableSpendingIncreaseAlerts(page);

    await createExpense(page, { amount: 100, date: previousMonthDate(), category, description: 'Almuerzo mes pasado' });
    await createExpense(page, { amount: 300, date: todayDate(), category, description: 'Almuerzo este mes' });

    await page.goto('/alerts?filter=spending');
    await expect(page.locator('.card', { hasText: category })).toBeVisible();

    await page.goto('/alerts?filter=budget');
    await expect(page.getByText('Sin alertas en este filtro.')).toBeVisible();

    await page.goto('/alerts');
    await expect(page.locator('.nav-pills .nav-link', { hasText: 'No leídas' }).locator('.badge')).toHaveText('1');
  });

  test('marking a single alert read removes the unread state and the button', async ({ page }) => {
    await signUp(page);
    const category = `Restaurantes-${Date.now()}`;
    await createCategory(page, category);
    await enableSpendingIncreaseAlerts(page);

    await createExpense(page, { amount: 100, date: previousMonthDate(), category, description: 'Almuerzo mes pasado' });
    await createExpense(page, { amount: 200, date: todayDate(), category, description: 'Almuerzo este mes' });

    await page.goto('/alerts');
    const card = page.locator('.card', { hasText: category });
    await expect(card.getByText('Marcar leída')).toBeVisible();

    await card.getByRole('button', { name: 'Marcar leída' }).click();

    await expect(card.getByText('Marcar leída')).toHaveCount(0);
    await expect(page.locator('.sidebar-link', { hasText: 'Alertas' }).locator('.badge')).toHaveCount(0);
  });

  test('view expenses link opens the filtered expenses for the alert', async ({ page }) => {
    await signUp(page);
    const category = `Restaurantes-${Date.now()}`;
    await createCategory(page, category);
    await enableSpendingIncreaseAlerts(page);

    await createExpense(page, { amount: 100, date: previousMonthDate(), category, description: 'Almuerzo mes pasado' });
    await createExpense(page, { amount: 200, date: todayDate(), category, description: 'Almuerzo este mes' });

    await page.goto('/alerts');
    const card = page.locator('.card', { hasText: category });
    await card.getByRole('link', { name: 'Ver gastos' }).click();

    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText('Almuerzo este mes').first()).toBeVisible();
  });
});
