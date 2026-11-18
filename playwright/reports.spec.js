const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');
const { pickCategory } = require('./helpers/category_picker');
const { createMoneySource } = require('./helpers/money_sources');

const REPORT_PAGES = [
  {
    name: 'overview',
    path: '/reports',
    title: 'Informes',
    selector: '[data-testid="overview-cards"]',
    period: true,
    checks: async (page) => {
      await expect(page.getByTestId('income-total')).toBeVisible();
      await expect(page.getByTestId('expenses-total')).toBeVisible();
      await expect(page.getByTestId('debt-total')).toBeVisible();
      await expect(page.getByTestId('net-cash-flow')).toBeVisible();
      await expect(page.getByTestId('cash-flow-empty')).toBeVisible();
      await expect(page.getByTestId('financial-analysis')).toBeVisible();
    }
  },
  {
    name: 'available cycle',
    path: '/reports/available_cycle',
    title: 'Disponible del ciclo',
    selector: '[data-testid="available-cycle"]',
    period: false,
    checks: async (page) => {
      await expect(page.getByTestId('remaining-money')).toBeVisible();
      await expect(page.getByTestId('current-money')).toBeVisible();
      await expect(page.getByTestId('pending-total')).toBeVisible();
      const percent = page.getByRole('button', { name: 'Porcentaje' });
      await percent.click();
      await expect(percent).toHaveAttribute('aria-pressed', 'true');
    }
  },
  {
    name: 'savings capacity',
    path: '/reports/savings_capacity',
    title: 'Capacidad de ahorro',
    selector: '[data-testid="savings-capacity"]',
    period: false,
    checks: async (page) => {
      await expect(page.locator('#savingsCapacityCycle')).toBeVisible();
      await expect(page.getByTestId('savings-capacity-result')).toBeVisible();
      await expect(page.getByTestId('savings-capacity-breakdown-result')).toBeVisible();
      await expect(page.locator('[data-savings-capacity-basic-toggle]')).toBeVisible();
    }
  },
  {
    name: 'category spending',
    path: '/reports/by_category',
    title: 'Gasto por categoría',
    selector: '[data-testid="category-summary"]',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByTestId('category-total')).toBeVisible();
      await expect(page.getByTestId('category-count')).toBeVisible();
      await expect(page.getByTestId('category-transactions')).toBeVisible();
      await expect(page.getByTestId('category-average')).toBeVisible();
      await expect(page.getByTestId('category-distribution-empty')).toBeVisible();
    }
  },
  {
    name: 'spending trend',
    path: '/reports/trends',
    title: 'Tendencia de gasto',
    selector: '[data-spending-trend-page]',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByTestId('trend-empty')).toBeVisible();
      await expect(page.getByText('No hay gastos registrados en este periodo.')).toBeVisible();
    }
  },
  {
    name: 'budgets',
    path: '/reports/budgets',
    title: 'Presupuesto vs. gasto',
    selector: '[data-testid="budget-report"]',
    period: true,
    categoryFilter: true,
    moneySourceFilter: false,
    checks: async (page) => {
      await expect(page.getByTestId('budget-metric-budget')).toBeVisible();
      await expect(page.getByTestId('budget-metric-actual')).toBeVisible();
      await expect(page.getByTestId('budget-metric-usage')).toBeVisible();
      await expect(page.getByText('No hay presupuestos activos todavía.').first()).toBeVisible();

      await page.getByTestId('budget-view-chart').click();
      await expect(page.getByTestId('budget-view-chart')).toHaveAttribute('aria-selected', 'true');
      await expect(page.getByTestId('budget-chart-view')).toBeVisible();
      await expect(page.locator('#budget-table-view')).toBeHidden();

      await page.getByTestId('budget-view-table').click();
      await expect(page.getByTestId('budget-view-table')).toHaveAttribute('aria-selected', 'true');
      await expect(page.locator('#budget-table-view')).toBeVisible();
    }
  },
  {
    name: 'credit cards',
    path: '/reports/credit_cards',
    title: 'Tarjetas de crédito',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByText('No tienes tarjetas de crédito registradas.')).toBeVisible();
    }
  },
  {
    name: 'loans',
    path: '/reports/loans',
    title: 'Préstamos y deuda',
    selector: '[data-testid="debt-consolidated"]',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByText('No tienes préstamos registrados.')).toBeVisible();
    }
  },
  {
    name: 'recurring',
    path: '/reports/recurring',
    title: 'Pagos recurrentes',
    selector: '[data-testid="recurring-monthly"]',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByTestId('recurring-annual')).toBeVisible();
      await expect(page.getByText('No hay pagos recurrentes registrados.').first()).toBeVisible();
    }
  },
  {
    name: 'money sources',
    path: '/reports/money_sources',
    title: 'Origen del gasto',
    selector: '[data-testid="money-sources-report"]',
    period: true,
    customFilters: true,
    checks: async (page) => {
      await expect(page.getByTestId('money-source-filters')).toBeVisible();
      await expect(page.getByTestId('money-source-empty')).toBeVisible();
      await expect(page.locator('#source_kind')).toBeVisible();
    }
  },
  {
    name: 'transfers',
    path: '/reports/transfers',
    title: 'Transferencias',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByText('No hay transferencias en este periodo.')).toBeVisible();
    }
  },
  {
    name: 'insights',
    path: '/reports/insights',
    title: 'Perspectivas financieras',
    selector: '[data-testid="perspectives-empty"]',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByText('Aún no hay movimientos en este ciclo')).toBeVisible();
    }
  },
  {
    name: 'transactions',
    path: '/reports/transactions',
    title: 'Transacciones',
    period: true,
    categoryFilter: true,
    moneySourceFilter: true,
    checks: async (page) => {
      await expect(page.getByText('No hay gastos en este periodo.')).toBeVisible();
    }
  }
];

test.describe('Reports section', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  for (const report of REPORT_PAGES) {
    test(`${report.name} report renders its main content`, async ({ page }) => {
      const response = await page.goto(report.path);

      expect(response.status()).toBe(200);
      await expect(page.locator('h1.reports-title')).toHaveText(report.title);
      if (report.selector) {
        await expect(page.locator(report.selector)).toBeVisible();
      }
      if (report.period) {
        await expect(page.locator('#report-period-select')).toBeVisible();
      }
      if (report.categoryFilter) {
        await expect(page.getByTestId('reports-category-picker')).toBeVisible();
      }
      if (report.moneySourceFilter) {
        await expect(page.locator('#money_source_id')).toBeVisible();
      }
      if (report.customFilters) {
        await expect(page.getByTestId('money-source-filters')).toBeVisible();
      }
      if (report.checks) {
        await report.checks(page);
      }
    });
  }

  test('period selector updates the report URL', async ({ page }) => {
    await page.goto('/reports');
    const select = page.locator('#report-period-select');
    const current = await select.inputValue();
    const next = await select.locator('option').evaluateAll((options, selected) => {
      const candidate = options.find((option) =>
        option.value && option.value !== selected && option.value !== 'custom');
      return candidate ? candidate.value : null;
    }, current);

    expect(next).toBeTruthy();
    await Promise.all([
      page.waitForURL(new RegExp(`period=${next}`)),
      select.selectOption(next)
    ]);
    await expect(select).toHaveValue(next);
    await expect(page.locator('h1.reports-title')).toHaveText('Informes');
  });

  test('money sources report filters by source kind', async ({ page }) => {
    await page.goto('/reports/money_sources');
    const filters = page.getByTestId('money-source-filters');

    await filters.locator('#source_kind').selectOption('cash');
    await filters.getByRole('button', { name: 'Filtrar' }).click();

    await expect(page).toHaveURL(/source_kind=cash/);
    await expect(page.getByTestId('money-source-empty-filtered')).toBeVisible();
  });

  test('category report opens the transaction drill-down modal', async ({ page }) => {
    const category = `Reporte Cat-${Date.now()}`;
    const source = `Cuenta Reporte-${Date.now()}`;
    const description = `Compra reporte ${Date.now()}`;

    await createCategory(page, category);
    await createMoneySource(page, source, 'account', { startingBalance: '3000000' });
    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('250000');
    await page.locator('#expense_description').fill(description);
    await pickCategory(page, 'expense_category_id', category);
    await page.locator('#expense_money_source_id').selectOption({ label: source });
    await page.getByRole('button', { name: 'Guardar' }).click();
    await expect(page).toHaveURL(/\/expenses/);

    await page.goto('/reports/by_category');
    const row = page.getByTestId('category-row').filter({ hasText: category });
    await expect(row).toBeVisible();
    await row.click();

    await expect(page.getByTestId('report-transactions-modal')).toBeVisible();
    await expect(page.getByTestId('report-transactions-modal-content')).toContainText(description);
  });
});
