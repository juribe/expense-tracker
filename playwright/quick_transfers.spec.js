const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');
const { createGoal } = require('./helpers/goals');

function accountCard(page, name) {
  return page.locator('[data-testid="account-card"]', { hasText: name }).first();
}

function pocketCard(page, name) {
  return page.locator('[data-testid="pocket-card"]', { hasText: name }).first();
}

async function openCardQuickAction(page, card, testId) {
  await card.getByTestId('card-actions-toggle').click();
  await card.getByTestId(testId).click();
  await expect(page.getByTestId('quick-transfer-form')).toBeVisible();
}

// Every manual transfer charges the 4x1.000 on the origin account. Marking it
// exempt keeps the assertions about the moved amount exact.
async function createExemptAccount(page, name, startingBalance) {
  return createMoneySource(page, name, 'account', {
    startingBalance,
    fill: async (page) => {
      await page.locator('[data-kind-panel~="account"] #money_source_gmf_exempt').check();
    }
  });
}

test.describe('quick transfers from a money source', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can withdraw cash from an account', async ({ page }) => {
    const cashName = `Efectivo Retiro-${Date.now()}`;
    const accountName = `Cuenta Retiro-${Date.now()}`;

    await createMoneySource(page, cashName, 'cash', { startingBalance: '0' });
    await createExemptAccount(page, accountName, '1000000');

    await page.goto('/money_sources/cash');
    await openCardQuickAction(page, accountCard(page, accountName), 'quick-action-withdraw');

    await page.locator('#transfer_amount').fill('250000');
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();
    await expect(accountCard(page, accountName).locator('.account-balance-amount')).toHaveText('$750.000');
    await expect(accountCard(page, cashName).locator('.account-balance-amount')).toHaveText('$250.000');
  });

  test('user can transfer money to another account', async ({ page }) => {
    const originName = `Cuenta Origen-${Date.now()}`;
    const targetName = `Cuenta Destino-${Date.now()}`;

    await createExemptAccount(page, originName, '1000000');
    await createMoneySource(page, targetName, 'account', { startingBalance: '0' });

    await page.goto('/money_sources/cash');
    await openCardQuickAction(page, accountCard(page, originName), 'quick-action-transfer');

    await page.locator('#transfer_to_source_id').selectOption({ label: targetName });
    await page.locator('#transfer_amount').fill('400000');
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();
    await expect(accountCard(page, originName).locator('.account-balance-amount')).toHaveText('$600.000');
    await expect(accountCard(page, targetName).locator('.account-balance-amount')).toHaveText('$400.000');
  });

  test('user can send money from an account to a pocket', async ({ page }) => {
    const accountName = `Cuenta Bolsillo-${Date.now()}`;
    const pocketName = `Bolsillo Destino-${Date.now()}`;

    await createExemptAccount(page, accountName, '1000000');
    await createMoneySource(page, pocketName, 'pocket', { startingBalance: '0' });

    await page.goto('/money_sources/cash');
    await openCardQuickAction(page, accountCard(page, accountName), 'quick-action-pocket');

    await page.locator('#transfer_to_source_id').selectOption({ label: pocketName });
    await page.locator('#transfer_amount').fill('300000');
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();
    await expect(accountCard(page, accountName).locator('.account-balance-amount')).toHaveText('$700.000');

    await page.goto('/money_sources/pockets');
    await expect(pocketCard(page, pocketName).getByTestId('pocket-card-total')).toHaveText('$300.000');
  });

  test('user can send money to a pocket and reserve it for a goal', async ({ page }) => {
    const accountName = `Cuenta Meta-${Date.now()}`;
    const pocketName = `Bolsillo Meta Rápida-${Date.now()}`;
    const goalName = `Moto Meta-${Date.now()}`;

    await createExemptAccount(page, accountName, '1000000');
    await createMoneySource(page, pocketName, 'pocket', { startingBalance: '0' });
    await createGoal(page, { name: goalName, target: '500000', pocket: pocketName });

    await page.goto('/money_sources/cash');
    await openCardQuickAction(page, accountCard(page, accountName), 'quick-action-pocket');

    await page.locator('#transfer_to_source_id').selectOption({ label: pocketName });
    await expect(page.locator('#quick-assign-goal-field')).toBeVisible();
    await page.locator('#quick_transfer_assign_goal_id').selectOption({ label: goalName });
    await page.locator('#transfer_amount').fill('200000');
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();

    await expect(page).toHaveURL(/\/money_sources\/cash$/);
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();

    await page.goto('/goals');
    const goal = page.locator('[data-testid="goal-card"]', { hasText: goalName }).first();
    await expect(goal.getByTestId('goal-card-saved')).toHaveText('$200.000');

    await page.goto('/money_sources/pockets');
    const pocket = pocketCard(page, pocketName);
    await expect(pocket.getByTestId('pocket-card-total')).toHaveText('$200.000');
    await expect(pocket.getByTestId('pocket-card-allocated')).toHaveText('$200.000');
    await expect(pocket.getByTestId('pocket-card-unallocated')).toHaveText('$0');
  });

  test('user can assign money to an existing pocket from the pocket card', async ({ page }) => {
    const accountName = `Cuenta Asignar-${Date.now()}`;
    const pocketName = `Bolsillo Asignar-${Date.now()}`;

    await createExemptAccount(page, accountName, '1000000');
    await createMoneySource(page, pocketName, 'pocket', { startingBalance: '0' });

    await page.goto('/money_sources/pockets');
    const pocket = pocketCard(page, pocketName);
    await pocket.getByTestId('quick-action-assign').click();
    await expect(page.getByTestId('quick-transfer-form')).toBeVisible();

    await page.locator('#transfer_from_source_id').selectOption({ label: accountName });
    await page.locator('#transfer_amount').fill('150000');
    await page.getByRole('button', { name: 'Crear Transferencia' }).click();

    await expect(page).toHaveURL(/\/money_sources\/pockets$/);
    await expect(page.getByText('La transferencia se creó correctamente.')).toBeVisible();
    await expect(pocketCard(page, pocketName).getByTestId('pocket-card-total')).toHaveText('$150.000');

    await page.goto('/money_sources/cash');
    await expect(accountCard(page, accountName).locator('.account-balance-amount')).toHaveText('$850.000');
  });
});
