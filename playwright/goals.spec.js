const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');
const { createGoal } = require('./helpers/goals');

function goalCard(page, name) {
  return page.locator('[data-testid="goal-card"]', { hasText: name }).first();
}

test.describe('savings goals', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can create a goal backed by a pocket', async ({ page }) => {
    const pocketName = `Bolsillo Meta-${Date.now()}`;
    const goalName = `Viaje Meta-${Date.now()}`;

    await createMoneySource(page, pocketName, 'pocket', { startingBalance: '0' });
    await createGoal(page, {
      name: goalName,
      target: '2000000',
      pocket: pocketName,
      targetDate: '2027-06-30'
    });

    const card = goalCard(page, goalName);
    await expect(card.getByTestId('goal-card-name')).toHaveText(goalName);
    await expect(card.getByTestId('goal-card-target')).toHaveText('$2.000.000');
    await expect(card.getByTestId('goal-card-saved')).toHaveText('$0');
    await expect(card.getByTestId('goal-card-pocket')).toContainText(pocketName);
    await expect(page.getByTestId('goals-summary-count')).toHaveText('1');
  });

  test('user can reserve pocket money for a goal and see the progress', async ({ page }) => {
    const pocketName = `Bolsillo Reserva-${Date.now()}`;
    const goalName = `Portátil Meta-${Date.now()}`;

    await createMoneySource(page, pocketName, 'pocket', { startingBalance: '500000' });
    await createGoal(page, { name: goalName, target: '1000000', pocket: pocketName });

    const card = goalCard(page, goalName);
    await card.getByRole('button', { name: 'Asignar a meta' }).click();

    const modal = page.locator('#assign-to-goal-modal');
    await expect(modal).toBeVisible();
    await expect(page.locator('#assign-to-goal-pocket-name')).toHaveText(pocketName);

    await page.locator('#goal_allocations_amount').fill('250000');
    await modal.getByRole('button', { name: 'Asignar a meta' }).click();

    await expect(page).toHaveURL(/\/goals$/);
    await expect(page.getByText('Dinero asignado a la meta.')).toBeVisible();

    const updatedCard = goalCard(page, goalName);
    await expect(updatedCard.getByTestId('goal-card-saved')).toHaveText('$250.000');
    await expect(updatedCard.getByTestId('goal-card-progress')).toHaveAttribute('aria-valuenow', '25');

    // The reservation lives inside the pocket: the total does not change, the
    // allocated share does.
    await page.goto('/money_sources/pockets');
    const pocket = page.locator('[data-testid="pocket-card"]', { hasText: pocketName }).first();
    await expect(pocket.getByTestId('pocket-card-total')).toHaveText('$500.000');
    await expect(pocket.getByTestId('pocket-card-allocated')).toHaveText('$250.000');
    await expect(pocket.getByTestId('pocket-card-unallocated')).toHaveText('$250.000');
  });

  test('without pockets the form explains how to start', async ({ page }) => {
    await page.goto('/goals/new');

    await expect(page.getByText('Aún no tienes bolsillos. Crea uno para empezar a asignar dinero a esta meta.')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Crear bolsillo' })).toHaveAttribute('href', /\/money_sources\/new\?kind=pocket/);
    await expect(page.locator('#goal_pocket_id')).toHaveCount(0);
  });
});
