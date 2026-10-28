const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('Credit cards and loans as money sources', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  function cardContaining(page, name) {
    return page.locator('[data-testid="credit-card-card"]', { hasText: name }).first();
  }

  function loanContaining(page, name) {
    return page.locator('[data-testid="loan-card"]', { hasText: name }).first();
  }

  test('user can create a credit card with credit-specific fields and see debt display', async ({ page }) => {
    const name = `TDC Prueba-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_credit_account_attributes_card_brand').selectOption('visa');
    await page.locator('#money_source_credit_account_attributes_card_last_four').fill('1234');
    await page.locator('#money_source_credit_account_attributes_credit_limit').fill('20000000');
    await page.locator('[data-kind-panel="credit_card"] #money_source_credit_account_attributes_interest_rate').fill('24.5');
    await page.locator('[data-kind-panel="credit_card"] #money_source_credit_account_attributes_interest_rate_type').selectOption('effective_annual');
    await page.locator('#money_source_credit_account_attributes_statement_day').fill('15');
    await page.locator('#money_source_credit_account_attributes_payment_due_day').fill('30');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();

    await expect(page).toHaveURL(/\/money_sources\/credit_cards$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = cardContaining(page, name);
    await expect(card.getByRole('heading', { name })).toBeVisible();
    await expect(card.getByText('Deuda actual')).toBeVisible();
    await expect(card.getByText('$0')).toBeVisible();
    await expect(card.getByText('Cupo aprobado')).toBeVisible();
    await expect(card.getByText('$20.000.000', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('Disponible').first()).toBeVisible();
    await expect(card.getByText('Tasa')).toBeVisible();
    await expect(card.getByText('24.50% EA')).toBeVisible();
    await expect(card.getByText('Corte')).toBeVisible();
    await expect(card.getByText('Pago', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('visa · 1234')).toBeVisible();
  });

  test('credit card show page displays approved/used/available credit', async ({ page }) => {
    const name = `TDC Show-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_credit_account_attributes_card_brand').selectOption('visa');
    await page.locator('#money_source_credit_account_attributes_card_last_four').fill('4321');
    await page.locator('#money_source_credit_account_attributes_credit_limit').fill('20000000');
    await page.locator('#money_source_credit_account_attributes_statement_day').fill('15');
    await page.locator('#money_source_credit_account_attributes_payment_due_day').fill('30');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = cardContaining(page, name);
    const editHref = await card.locator('a[href$="/edit"]').getAttribute('href');
    await page.goto(editHref.replace(/\/edit$/, ''));

    await expect(page.getByRole('heading', { name })).toBeVisible();
    await expect(page.getByText('Aprobado', { exact: true })).toBeVisible();
    await expect(page.getByText('Usado', { exact: true })).toBeVisible();
    await expect(page.getByText('Disponible', { exact: true }).first()).toBeVisible();
    await expect(page.getByText('$20.000.000', { exact: true }).first()).toBeVisible();
    await expect(page.getByText(/Próxima factura el día 15, pago vence el día 30/)).toBeVisible();
  });

  test('user can create a loan with installment fields and see outstanding debt', async ({ page }) => {
    const name = `Préstamo Auto-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('loan');
    await page.locator('#money_source_credit_account_attributes_principal_amount').fill('114000000');
    await page.locator('[data-kind-panel="loan"] #money_source_credit_account_attributes_interest_rate').fill('21.27');
    await page.locator('[data-kind-panel="loan"] #money_source_credit_account_attributes_interest_rate_type').selectOption('effective_annual');
    await page.locator('#money_source_credit_account_attributes_installment_amount').fill('1800000');
    await page.locator('#money_source_credit_account_attributes_installment_count').fill('72');
    await page.locator('#money_source_credit_account_attributes_payment_frequency').selectOption('monthly');
    await page.locator('#money_source_credit_account_attributes_start_date').fill('01/01/2025');
    await page.locator('#money_source_credit_account_attributes_end_date').fill('31/12/2030');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();

    await expect(page).toHaveURL(/\/money_sources\/loans$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = loanContaining(page, name);
    await expect(card.getByRole('heading', { name })).toBeVisible();
    await expect(card.getByText('Saldo pendiente')).toBeVisible();
    await expect(card.getByText('$114.000.000', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('Original')).toBeVisible();
    await expect(card.getByText('Tasa EA')).toBeVisible();
    await expect(card.getByText('21.27% EA')).toBeVisible();
    await expect(card.getByText('Cuota mensual')).toBeVisible();
    await expect(card.getByText('$1.800.000', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('72 de 72')).toBeVisible();
  });

  test('account money source hides credit/debt-specific fields in the form', async ({ page }) => {
    await page.goto('/money_sources/new');
    await page.locator('#money_source_kind').selectOption('account');
    await expect(page.locator('#money_source_credit_account_attributes_credit_limit')).toBeHidden();
    await expect(page.locator('#money_source_credit_account_attributes_principal_amount')).toBeHidden();
    await expect(page.locator('[data-kind-panel="credit_card"]')).toBeHidden();
    await expect(page.locator('[data-kind-panel="loan"]')).toBeHidden();
  });

  test('credit cards section opens the form with the card kind preselected and hidden', async ({ page }) => {
    await page.goto('/money_sources/credit_cards');

    await page.getByRole('link', { name: 'Nueva tarjeta de crédito' }).first().click();

    await expect(page).toHaveURL(/\/money_sources\/new\?kind=credit_card$/);
    await expect(page.getByRole('heading', { name: 'Nueva tarjeta de crédito' })).toBeVisible();
    const kind = page.locator('#money_source_kind');
    await expect(kind).toHaveAttribute('type', 'hidden');
    await expect(kind).toHaveValue('credit_card');
    await expect(page.locator('[data-kind-panel="credit_card"]')).toBeVisible();
    await expect(page.locator('[data-kind-panel="loan"]')).toBeHidden();
    await expect(page.getByRole('button', { name: 'Guardar tarjeta de crédito' })).toBeVisible();
  });

  test('cash section menu opens the form with the chosen kind preselected', async ({ page }) => {
    await page.goto('/money_sources/cash');

    await page.getByTestId('new-source-menu').first().click();
    await page.getByTestId('new-source-kind-account').first().click();

    await expect(page).toHaveURL(/\/money_sources\/new\?kind=account$/);
    await expect(page.getByRole('heading', { name: 'Nueva cuenta' })).toBeVisible();
    await expect(page.locator('#money_source_kind')).toHaveValue('account');
    await expect(page.locator('[data-kind-panel="account wallet"]')).toBeVisible();
    await expect(page.locator('[data-kind-panel="credit_card"]')).toBeHidden();
  });

  test('cash money source only asks for the starting balance', async ({ page }) => {
    await page.goto('/money_sources/cash');

    await page.getByTestId('new-source-menu').first().click();
    await page.getByTestId('new-source-kind-cash').first().click();

    await expect(page).toHaveURL(/\/money_sources\/new\?kind=cash$/);
    await expect(page.getByRole('heading', { name: 'Nuevo efectivo' })).toBeVisible();
    await expect(page.locator('#money_source_name')).toHaveAttribute('placeholder', 'p. ej. Efectivo');
    const cashPanel = page.locator('[data-kind-panel="cash"]');
    await expect(cashPanel.locator('#money_source_starting_balance')).toBeVisible();
    await expect(cashPanel.locator('[data-institution-combobox]')).toHaveCount(0);
    await expect(cashPanel.locator('#money_source_identifier')).toHaveCount(0);
  });

  test('name placeholder follows the selected kind in the generic form', async ({ page }) => {
    await page.goto('/money_sources/new');

    const name = page.locator('#money_source_name');
    await expect(name).toHaveAttribute('placeholder', 'p. ej. Ahorros Bancolombia');

    await page.locator('#money_source_kind').selectOption('credit_card');
    await expect(name).toHaveAttribute('placeholder', 'p. ej. Tarjeta Gold');

    await page.locator('#money_source_kind').selectOption('cash');
    await expect(name).toHaveAttribute('placeholder', 'p. ej. Efectivo');
  });
});