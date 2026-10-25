const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

test.describe('Money source statement (extracto)', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('shows movements tab and opens detail modal', async ({ page }) => {
    const name = `Cuenta ${Date.now()}`;
    await createMoneySource(page, name, 'account', { startingBalance: '2000000' });

    await page.goto('/money_sources/cash');
    await page.locator('a[href^="/money_sources/"]').filter({ hasText: name }).first().click();

    await page.getByRole('tab', { name: /Movimientos/i }).click();
    await expect(page.locator('#movementRows')).toBeVisible();

    // empty state allowed; if rows exist, open modal
    const rows = page.locator('.statement-row');
    const count = await rows.count();
    if (count > 0) {
      await rows.first().click();
      await expect(page.locator('#movementDetailModal')).toBeVisible();
    }
  });

  test('filters and search update results', async ({ page }) => {
    const name = `Cuenta ${Date.now()}`;
    await createMoneySource(page, name, 'account', { startingBalance: '2000000' });

    await page.goto('/money_sources/cash');
    await page.locator('a[href^="/money_sources/"]').filter({ hasText: name }).first().click();
    await page.getByRole('tab', { name: /Movimientos/i }).click();

    // search non-existent text -> empty state
    await page.locator('input[name="q"]').fill('no-existe-xyz');
    await page.locator('button[aria-label="Buscar movimientos"]').click();
    await expect(page.getByText(/No hay movimientos que coincidan/)).toBeVisible();
  });
});
