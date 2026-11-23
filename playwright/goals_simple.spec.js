const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

function goalCard(page, name) {
  return page.locator('[data-testid="goal-card"]', { hasText: name }).first();
}

test.describe('simple savings goals', () => {
  test('user can create a goal without a pocket and move money virtually', async ({ page }) => {
    await signUp(page, { moneyTrackingMode: 'simple' });
    const name = `Meta simple-${Date.now()}`;

    await page.goto('/goals/new');
    await expect(page.locator('#goal_pocket_id')).toHaveCount(0);
    await page.locator('#goal_name').fill(name);
    await page.locator('#goal_target_amount').fill('1000000');
    await page.getByRole('button', { name: 'Crear meta' }).click();

    await expect(page).toHaveURL(/\/goals$/);
    const card = goalCard(page, name);
    await expect(card.getByTestId('goal-card-pocket')).toHaveCount(0);

    await card.getByTestId('goal-add-money').click();
    await expect(page.getByTestId('goal-contribution-deposit')).toBeVisible();
    await expect(page.getByTestId('goal-contribution-withdraw')).toBeHidden();
    await page.locator('#goal_contribution_amount').fill('300000');
    await page.getByTestId('goal-contribution-deposit').click();

    await expect(page.getByText('Dinero asignado a la meta.')).toBeVisible();
    await expect(goalCard(page, name).getByTestId('goal-card-saved')).toHaveText('$300.000');

    await goalCard(page, name).getByTestId('goal-withdraw-money').click();
    await expect(page.getByTestId('goal-contribution-withdraw')).toBeVisible();
    await expect(page.getByTestId('goal-contribution-deposit')).toBeHidden();
    await page.locator('#goal_contribution_amount').fill('100000');
    await page.getByTestId('goal-contribution-withdraw').click();

    await expect(page.getByText('Retiro registrado en la meta.')).toBeVisible();
    await expect(goalCard(page, name).getByTestId('goal-card-saved')).toHaveText('$200.000');

    await goalCard(page, name).getByTestId('goal-history').locator('summary').click();
    await expect(goalCard(page, name).getByTestId('goal-history')).toContainText('Aporte');
    await expect(goalCard(page, name).getByTestId('goal-history')).toContainText('Retiro');
  });
});
