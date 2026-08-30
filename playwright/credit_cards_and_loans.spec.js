const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('Credit cards and loans as money sources', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  function cardContaining(page, name) {
    return page.locator('.card', { hasText: name }).first();
  }

  test('user can create a credit card with credit-specific fields and see debt display', async ({ page }) => {
    const name = `TDC Prueba-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('[data-kind-panel="credit_card"] #money_source_bank').fill('Bancolombia');
    await page.locator('#money_source_credit_account_attributes_card_brand').selectOption('visa');
    await page.locator('#money_source_credit_account_attributes_card_last_four').fill('1234');
    await page.locator('#money_source_credit_account_attributes_credit_limit').fill('20000000');
    await page.locator('[data-kind-panel="credit_card"] #money_source_credit_account_attributes_interest_rate').fill('24.5');
    await page.locator('[data-kind-panel="credit_card"] #money_source_credit_account_attributes_interest_rate_type').selectOption('effective_annual');
    await page.locator('#money_source_credit_account_attributes_statement_day').fill('15');
    await page.locator('#money_source_credit_account_attributes_payment_due_day').fill('30');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();

    await expect(page).toHaveURL(/\/money_sources$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    await expect(page.getByText('Crédito y Deuda')).toBeVisible();
    const card = cardContaining(page, name);
    await expect(card.getByText('Crédito disponible')).toBeVisible();
    await expect(card.getByText('de $20.000.000')).toBeVisible();
    await expect(card.getByText('Usado $0')).toBeVisible();
    await expect(card.getByText('24.50% EA')).toBeVisible();
    await expect(card.getByText('Facturación: 15')).toBeVisible();
    await expect(card.getByText('Vence: 30')).toBeVisible();
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
    await expect(page.getByText('Disponible')).toBeVisible();
    await expect(page.getByText('$20.000.000', { exact: true }).first()).toBeVisible();
    await expect(page.getByText(/Próxima factura el día 15, pago vence el día 30/)).toBeVisible();
  });

  test('user can create a loan with installment fields and see outstanding debt', async ({ page }) => {
    const name = `Préstamo Auto-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('loan');
    await page.locator('[data-kind-panel="loan"] #money_source_bank').fill('Banco');
    await page.locator('#money_source_credit_account_attributes_principal_amount').fill('114000000');
    await page.locator('[data-kind-panel="loan"] #money_source_credit_account_attributes_interest_rate').fill('21.27');
    await page.locator('[data-kind-panel="loan"] #money_source_credit_account_attributes_interest_rate_type').selectOption('effective_annual');
    await page.locator('#money_source_credit_account_attributes_installment_amount').fill('1800000');
    await page.locator('#money_source_credit_account_attributes_installment_count').fill('72');
    await page.locator('#money_source_credit_account_attributes_payment_frequency').selectOption('monthly');
    await page.locator('#money_source_credit_account_attributes_start_date').fill('2025-01-01');
    await page.locator('#money_source_credit_account_attributes_end_date').fill('2030-12-31');
    await page.locator('#money_source_active').check();
    await page.locator('form input[type="submit"]').click();

    await expect(page).toHaveURL(/\/money_sources$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    await expect(page.getByText('Crédito y Deuda')).toBeVisible();
    const card = cardContaining(page, name);
    await expect(card.getByText('Saldo pendiente')).toBeVisible();
    await expect(card.getByText('$114.000.000', { exact: true })).toBeVisible();
    await expect(card.getByText('Original $114.000.000')).toBeVisible();
    await expect(card.getByText('21.27% EA')).toBeVisible();
    await expect(card.getByText('$1.800.000/Mensual')).toBeVisible();
    await expect(card.getByText('72 de 72 cuotas restantes')).toBeVisible();
  });

  test('account money source hides credit/debt-specific fields in the form', async ({ page }) => {
    await page.goto('/money_sources/new');
    await page.locator('#money_source_kind').selectOption('account');
    await expect(page.locator('#money_source_credit_account_attributes_credit_limit')).toBeHidden();
    await expect(page.locator('#money_source_credit_account_attributes_principal_amount')).toBeHidden();
    await expect(page.locator('[data-kind-panel="credit_card"]')).toBeHidden();
    await expect(page.locator('[data-kind-panel="loan"]')).toBeHidden();
  });
});