const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

function accountCard(page, name) {
  return page.locator('[data-testid="account-card"]', { hasText: name }).first();
}

function pocketCard(page, name) {
  return page.locator('[data-testid="pocket-card"]', { hasText: name }).first();
}

async function submitMoneySource(page) {
  await page.locator('form[data-money-source-form] button[type="submit"]').click();
}

test.describe('money source creation', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can create an account with a starting balance', async ({ page }) => {
    const name = `Ahorros Crud-${Date.now()}`;

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('account');
    await page.locator('[data-kind-panel~="account"] #money_source_starting_balance').fill('2500000');
    await page.locator('[data-kind-panel~="account"] #money_source_identifier').fill('4321');
    await page.locator('#money_source_active').check();
    await submitMoneySource(page);

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = accountCard(page, name);
    await expect(card.getByRole('heading', { name })).toBeVisible();
    await expect(card.locator('.account-balance-amount')).toHaveText('$2.500.000');

    // The last four digits are not shown on the card, so confirm they were
    // persisted by reopening the edit form.
    const editHref = await card.locator('a[href$="/edit"]').getAttribute('href');
    await page.goto(editHref);
    await expect(page.locator('[data-kind-panel~="account"] #money_source_identifier')).toHaveValue('4321');
  });

  test('user can create a credit card with its own fields', async ({ page }) => {
    const name = `TDC Crud-${Date.now()}`;

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_credit_account_attributes_card_brand').selectOption('visa');
    await page.locator('#money_source_credit_account_attributes_card_last_four').fill('1234');
    await page.locator('#money_source_credit_account_attributes_credit_limit').fill('8000000');
    await page.locator('[data-kind-panel="credit_card"] #money_source_credit_account_attributes_interest_rate').fill('24.5');
    await page.locator('[data-kind-panel="credit_card"] #money_source_credit_account_attributes_interest_rate_type')
              .selectOption('effective_annual');
    await page.locator('#money_source_credit_account_attributes_statement_day').fill('15');
    await page.locator('#money_source_credit_account_attributes_payment_due_day').fill('30');
    await page.locator('#money_source_active').check();
    await submitMoneySource(page);

    await expect(page).toHaveURL(/\/money_sources\/credit_cards$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = page.locator('[data-testid="credit-card-card"]', { hasText: name }).first();
    await expect(card.getByRole('heading', { name })).toBeVisible();
    await expect(card.getByText('visa · 1234')).toBeVisible();
    await expect(card.getByText('$8.000.000', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('24.50% EA')).toBeVisible();
  });

  test('user can create a loan with installment fields', async ({ page }) => {
    const name = `Préstamo Crud-${Date.now()}`;

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('loan');
    await page.locator('#money_source_sub_kind').selectOption('personal');
    await page.locator('#money_source_credit_account_attributes_principal_amount').fill('12000000');
    await page.locator('[data-kind-panel="loan"] #money_source_credit_account_attributes_interest_rate').fill('1.8');
    await page.locator('[data-kind-panel="loan"] #money_source_credit_account_attributes_interest_rate_type')
              .selectOption('monthly');
    await page.locator('#money_source_credit_account_attributes_installment_amount').fill('500000');
    await page.locator('#money_source_credit_account_attributes_installment_count').fill('24');
    await page.locator('#money_source_credit_account_attributes_start_date').fill('05/01/2026');
    await page.locator('#money_source_active').check();
    await submitMoneySource(page);

    await expect(page).toHaveURL(/\/money_sources\/loans$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = page.locator('[data-testid="loan-card"]', { hasText: name }).first();
    await expect(card.getByRole('heading', { name })).toBeVisible();
    await expect(card.getByText('Saldo pendiente')).toBeVisible();
    await expect(card.getByText('$12.000.000', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('1.80% M')).toBeVisible();
    await expect(card.getByText('$500.000', { exact: true }).first()).toBeVisible();
    await expect(card.getByText('24 de 24')).toBeVisible();
  });

  test('user can create a pocket with a starting balance', async ({ page }) => {
    const name = `Bolsillo Crud-${Date.now()}`;

    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('pocket');
    await page.locator('[data-kind-panel="pocket"] #money_source_starting_balance').fill('300000');
    await submitMoneySource(page);

    await expect(page).toHaveURL(/\/money_sources\/pockets$/);
    await expect(page.getByText('La fuente de dinero se creó correctamente.')).toBeVisible();

    const card = pocketCard(page, name);
    await expect(card.getByTestId('pocket-card-name')).toHaveText(name);
    await expect(card.getByTestId('pocket-card-total')).toHaveText('$300.000');
    await expect(card.getByTestId('pocket-card-unallocated')).toHaveText('$300.000');
  });
});

test.describe('account editing and deletion', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can edit an account name and balance', async ({ page }) => {
    const original = `Cuenta Editar-${Date.now()}`;
    const updated = `${original} editada`;
    await createMoneySource(page, original, 'account', { startingBalance: '1000000' });

    await page.goto('/money_sources/cash');
    const card = accountCard(page, original);
    await card.getByTestId('card-actions-toggle').click();
    await card.getByRole('link', { name: 'Editar', exact: true }).click();

    await expect(page).toHaveURL(/\/money_sources\/[0-9a-f-]{36}\/edit/);
    await expect(page.locator('#money_source_name')).toHaveValue(original);

    await page.locator('#money_source_name').fill(updated);
    await page.locator('[data-kind-panel~="account"] #money_source_starting_balance').fill('1500000');
    await submitMoneySource(page);

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La fuente de dinero se actualizó correctamente.')).toBeVisible();

    const editedCard = accountCard(page, updated);
    await expect(editedCard.getByRole('heading', { name: updated })).toBeVisible();
    await expect(editedCard.locator('.account-balance-amount')).toHaveText('$1.500.000');
    await expect(page.getByText(original, { exact: true })).toHaveCount(0);
  });

  test('user can delete an account without movements', async ({ page }) => {
    const name = `Cuenta Borrar-${Date.now()}`;
    await createMoneySource(page, name, 'account', { startingBalance: '0' });

    await page.goto('/money_sources/cash');
    const card = accountCard(page, name);
    await expect(card).toBeVisible();

    await card.getByTestId('card-actions-toggle').click();
    await card.getByRole('button', { name: 'Eliminar' }).click();
    await page.getByTestId('dialog-accept').click();

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La fuente de dinero se eliminó correctamente.')).toBeVisible();
    await expect(page.getByText(name, { exact: true })).toHaveCount(0);
  });
});
