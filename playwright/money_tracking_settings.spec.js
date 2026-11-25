const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('money tracking settings', () => {
  test('card selection drives the update button and keeps the existing flow', async ({ page }) => {
    await signUp(page, { moneyTrackingMode: 'simple' });
    await page.goto('/settings/money_tracking');

    const submit = page.getByTestId('money-tracking-submit');
    const simpleOption = page.getByTestId('money-tracking-option-simple');
    const detailedOption = page.getByTestId('money-tracking-option-detailed');
    const status = page.getByTestId('money-tracking-status');

    await expect(page.getByTestId('money-tracking-current-mode')).toHaveText('Simple');
    await expect(simpleOption).toHaveClass(/is-selected/);
    await expect(detailedOption).not.toHaveClass(/is-selected/);
    await expect(submit).toBeDisabled();
    await expect(status).toHaveText(/Tu modalidad actual es Seguimiento simple/);

    await detailedOption.click();
    await expect(detailedOption).toHaveClass(/is-selected/);
    await expect(simpleOption).not.toHaveClass(/is-selected/);
    await expect(submit).toBeEnabled();
    await expect(status).toHaveText(/Vas a cambiar a Seguimiento completo/);

    await simpleOption.click();
    await expect(submit).toBeDisabled();

    await detailedOption.click();
    await submit.click();

    // Both directions ask for confirmation before applying the change.
    await expect(page.getByTestId('money-tracking-confirm')).toBeVisible();
    await expect(page.getByTestId('money-tracking-confirm')).toContainText('Estás por activar el seguimiento completo');
    await expect(page.locator('.mt-confirm-change')).toHaveCount(4);
    await expect(page.getByText('Puedes volver a Seguimiento simple')).toBeVisible();
    await expect(page.getByTestId('money-tracking-confirm-submit')).toHaveText('Sí, activar seguimiento completo');

    // Cancelling keeps the current mode.
    await page.getByRole('link', { name: 'Cancelar' }).click();
    await expect(page.getByTestId('money-tracking-current-mode')).toHaveText('Simple');
    await expect(page.getByTestId('money-tracking-submit')).toBeDisabled();

    await detailedOption.click();
    await submit.click();
    await page.getByTestId('money-tracking-confirm-submit').click();

    await expect(page).toHaveURL(/\/settings\/money_tracking$/);
    await expect(page.getByTestId('money-tracking-current-mode')).toHaveText('Completo');
    await expect(page.getByTestId('money-tracking-submit')).toBeDisabled();

    await page.getByTestId('money-tracking-option-simple').click();
    await page.getByTestId('money-tracking-submit').click();
    await expect(page.getByTestId('money-tracking-confirm')).toContainText('Volverás al seguimiento simple');
    await expect(page.locator('.mt-confirm-change')).toHaveCount(4);
    await expect(page.getByText('No perderás tu información')).toBeVisible();
    await expect(page.getByTestId('money-tracking-confirm-submit')).toHaveText('Sí, volver a seguimiento simple');

    await page.getByRole('link', { name: 'Cancelar' }).click();
    await expect(page.getByTestId('money-tracking-current-mode')).toHaveText('Completo');
    await page.getByTestId('money-tracking-option-simple').click();
    await page.getByTestId('money-tracking-submit').click();
    await expect(page.getByTestId('money-tracking-confirm')).toContainText('Volverás al seguimiento simple');
    await page.getByTestId('money-tracking-confirm-submit').click();

    await expect(page).toHaveURL(/\/settings\/money_tracking$/);
    await expect(page.getByTestId('money-tracking-current-mode')).toHaveText('Simple');
    await expect(page.getByTestId('money-tracking-submit')).toBeDisabled();
  });

  test('options stack without horizontal scroll on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signUp(page, { moneyTrackingMode: 'simple' });
    await page.goto('/settings/money_tracking');

    const simpleOption = page.getByTestId('money-tracking-option-simple');
    const detailedOption = page.getByTestId('money-tracking-option-detailed');
    await expect(simpleOption).toBeVisible();

    const simpleBox = await simpleOption.boundingBox();
    const detailedBox = await detailedOption.boundingBox();
    expect(simpleBox).not.toBeNull();
    expect(detailedBox).not.toBeNull();
    expect(detailedBox.y).toBeGreaterThan(simpleBox.y + simpleBox.height - 1);

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow).toBeLessThanOrEqual(1);
  });

  test('confirmation stacks cards and actions on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signUp(page, { moneyTrackingMode: 'simple' });
    await page.goto('/settings/money_tracking');
    await page.getByTestId('money-tracking-option-detailed').click();
    await page.getByTestId('money-tracking-submit').click();

    await expect(page.getByTestId('money-tracking-confirm')).toBeVisible();
    const changes = page.locator('.mt-confirm-change');
    await expect(changes).toHaveCount(4);

    const first = await changes.nth(0).boundingBox();
    const second = await changes.nth(1).boundingBox();
    expect(second.y).toBeGreaterThan(first.y + first.height - 1);

    const submitBox = await page.getByTestId('money-tracking-confirm-submit').boundingBox();
    const panelBox = await page.locator('.mt-confirm-panel').boundingBox();
    expect(submitBox.width).toBeGreaterThan(panelBox.width * 0.8);

    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow).toBeLessThanOrEqual(1);

    // The reverse confirmation uses the same stacked layout.
    await page.getByTestId('money-tracking-confirm-submit').click();
    await expect(page.getByTestId('money-tracking-current-mode')).toHaveText('Completo');
    await page.getByTestId('money-tracking-option-simple').click();
    await page.getByTestId('money-tracking-submit').click();

    await expect(page.getByTestId('money-tracking-confirm')).toContainText('Volverás al seguimiento simple');
    await expect(page.locator('.mt-confirm-change')).toHaveCount(4);

    const simpleFirst = await page.locator('.mt-confirm-change').nth(0).boundingBox();
    const simpleSecond = await page.locator('.mt-confirm-change').nth(1).boundingBox();
    expect(simpleSecond.y).toBeGreaterThan(simpleFirst.y + simpleFirst.height - 1);

    const simpleOverflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(simpleOverflow).toBeLessThanOrEqual(1);
  });
});
