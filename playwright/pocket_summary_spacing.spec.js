const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

test.describe('Pocket summary spacing', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('keeps a visible gap between the balance and goals cards', async ({ page }) => {
    const name = `Bolsillo Espacio-${Date.now()}`;
    await createMoneySource(page, name, 'pocket', { startingBalance: '100000' });

    const card = page.locator('[data-testid="pocket-card"]', { hasText: name }).first();
    await card.locator('[data-testid="card-actions-toggle"]').click();
    await card.getByRole('link', { name: 'Ver detalle' }).click();

    const balanceCard = page.locator('[data-testid="pocket-summary"]');
    const goalsCard = page.locator('#pocket-goals');
    await expect(balanceCard).toBeVisible();
    await expect(goalsCard).toBeVisible();

    const balanceBox = await balanceCard.boundingBox();
    const goalsBox = await goalsCard.boundingBox();
    expect(balanceBox).not.toBeNull();
    expect(goalsBox).not.toBeNull();

    const gap = goalsBox.y - (balanceBox.y + balanceBox.height);
    expect(gap).toBeGreaterThanOrEqual(16);
  });
});
