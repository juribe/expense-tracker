const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createMoneySource } = require('./helpers/money_sources');

test.describe('Guided money-source recognition wizard', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('opens on the explanation and keeps comma-separated tags synced', async ({ page }) => {
    await createMoneySource(page, 'Cuenta Playwright', 'account');
    await createMoneySource(page, 'Efectivo Playwright', 'cash');

    await page.goto('/money_sources/recognition');
    await page.getByTestId('guided-recognition-open').click();

    await expect(page.getByTestId('guided-wizard-modal')).toBeVisible();
    await expect(page.locator('[data-guided-intro]')).toBeVisible();
    await expect(
      page.getByRole('heading', { name: 'Enseñémosle a Yogasto a reconocer tus fuentes' })
    ).toBeVisible();

    await page.getByTestId('guided-save').click();
    const firstStep = page.locator('form[data-guided-step-index="0"]');
    await expect(firstStep).toBeVisible();

    await firstStep.locator('[data-guided-keyword-input]').fill('tc credito, tc caja social');
    await firstStep.locator('[data-guided-keyword-add]').click();

    await expect(firstStep.locator('[data-testid="guided-alias-chip"]', { hasText: 'tc credito' })).toBeVisible();
    await expect(firstStep.locator('[data-testid="guided-alias-chip"]', { hasText: 'tc caja social' })).toBeVisible();
    await expect(firstStep.locator('input[name="keywords[]"][value="tc credito"]')).toHaveCount(1);
    await expect(firstStep.locator('input[name="keywords[]"][value="tc caja social"]')).toHaveCount(1);
    await expect(
      firstStep.locator('input[name="keywords[]"][value="tc credito, tc caja social"]')
    ).toHaveCount(0);

    // Deleting from the alias side removes the shared criterion.
    const aliasChip = firstStep.locator('[data-testid="guided-alias-chip"]', { hasText: 'tc credito' });
    await aliasChip.locator('[data-guided-alias-remove]').click();
    await expect(firstStep.locator('input[name="keywords[]"][value="tc credito"]')).toHaveCount(0);
    await expect(firstStep.locator('[data-testid="guided-alias-chip"]', { hasText: 'tc credito' })).toHaveCount(0);

    await page.getByTestId('guided-save').click();
    await expect(page.locator('form[data-guided-step-index="1"]')).toBeVisible();
  });

  test('cash hides email and save-and-exit persists the aliases', async ({ page }) => {
    await createMoneySource(page, 'Efectivo Playwright', 'cash');

    await page.goto('/money_sources/recognition');
    await page.getByTestId('guided-recognition-open').click();
    await expect(page.getByTestId('guided-wizard-modal')).toBeVisible();

    await page.getByTestId('guided-save').click();
    const cashStep = page.locator('form[data-guided-step-index="0"]');
    await expect(cashStep).toBeVisible();
    await expect(cashStep.locator('[data-testid="guided-email-section"]')).toHaveCount(0);

    await cashStep.locator('[data-guided-alias-input]').fill('efectivo, cash');
    await cashStep.locator('[data-guided-alias-add]').click();
    await expect(cashStep.locator('[data-testid="guided-alias-chip"]')).toHaveCount(2);

    await page.getByTestId('guided-exit-save').click();

    await expect(page).toHaveURL(/\/money_sources\/recognition$/);
    await expect(
      page.getByTestId('recognition-row').filter({ hasText: 'Efectivo Playwright' })
    ).toContainText('efectivo, cash');
  });
});
