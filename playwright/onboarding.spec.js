const { test, expect } = require('@playwright/test');
const { signUp, signIn } = require('./helpers/auth');

function card(page, step) {
  return page.getByTestId(`onboarding-card-${step}`);
}

async function skipCard(page, step) {
  await page.getByTestId(`onboarding-skip-${step}`).click();
  await page.waitForLoadState('load');
}

test.describe('dashboard onboarding banner', () => {
  test('a fresh user sees the three setup cards in order', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');

    const banner = page.getByTestId('onboarding');
    await expect(banner).toBeVisible();
    await expect(page.getByText('Completa tu configuración inicial')).toBeVisible();
    const cards = page.locator('[data-testid^="onboarding-card-"]');
    await expect(cards).toHaveCount(3);
    await expect(card(page, 'initial').locator('.onboarding-card-number')).toHaveText('1');
    await expect(card(page, 'gmail')).toBeVisible();
    await expect(card(page, 'whatsapp')).toBeVisible();
  });

  test('the main action opens the existing setup flows', async ({ page }) => {
    await signUp(page);
    await page.goto('/dashboard');
    await page.getByTestId('onboarding-cta-gmail').click();
    await expect(page).toHaveURL(/\/settings\/gmail/);
  });

  test('skipping a step persists after reload and keeps the others', async ({ page }) => {
    const account = await signUp(page);
    await page.goto('/dashboard');

    await skipCard(page, 'gmail');
    await page.goto('/dashboard');
    await expect(card(page, 'gmail')).toHaveCount(0);
    await expect(card(page, 'initial')).toBeVisible();
    await expect(card(page, 'whatsapp')).toBeVisible();

    // The skip is stored in the backend, not in this browser only.
    await page.context().close();
    const second = await page.context().browser().newContext();
    const freshPage = await second.newPage();
    await signIn(freshPage, account.email, account.password);
    await freshPage.goto('/dashboard');
    await expect(card(freshPage, 'gmail')).toHaveCount(0);
    await expect(card(freshPage, 'initial')).toBeVisible();
    await second.close();
  });

  test('closing with the X hides the banner only for the current session', async ({ page }) => {
    const account = await signUp(page);
    await page.goto('/dashboard');

    await page.getByTestId('onboarding-dismiss').click();
    await expect(page.getByTestId('onboarding')).toBeHidden();

    await page.goto('/dashboard');
    await expect(page.getByTestId('onboarding')).toBeHidden();

    // A new session (new browser storage) shows the banner again and no step
    // was persisted as skipped.
    await page.context().close();
    const second = await page.context().browser().newContext();
    const freshPage = await second.newPage();
    await signIn(freshPage, account.email, account.password);
    await freshPage.goto('/dashboard');
    await expect(freshPage.getByTestId('onboarding')).toBeVisible();
    await second.close();
  });

  test('skip the whole setup removes the banner permanently', async ({ page }) => {
    const account = await signUp(page);
    await page.goto('/dashboard');

    await page.getByTestId('onboarding-skip-all').click();
    await page.waitForLoadState('load');
    await expect(page.getByTestId('onboarding')).toHaveCount(0);

    await page.context().close();
    const second = await page.context().browser().newContext();
    const freshPage = await second.newPage();
    await signIn(freshPage, account.email, account.password);
    await freshPage.goto('/dashboard');
    await expect(freshPage.getByTestId('onboarding')).toHaveCount(0);
    await second.close();
  });

  test('keeping a step later ("No ahora") hides it for the session only and restores it in a new session', async ({ page }) => {
    const account = await signUp(page);
    await page.goto('/dashboard');

    await page.getByTestId('onboarding-later-gmail').click();
    await expect(card(page, 'gmail')).toBeHidden();
    await expect(card(page, 'initial')).toBeVisible();

    // Same browser session (reload): the postponement survives, nothing was
    // persisted in the backend.
    await page.goto('/dashboard');
    await expect(card(page, 'gmail')).toBeHidden();
    await expect(card(page, 'initial')).toBeVisible();

    await page.context().close();
    const second = await page.context().browser().newContext();
    const freshPage = await second.newPage();
    await signIn(freshPage, account.email, account.password);
    await freshPage.goto('/dashboard');
    await expect(card(freshPage, 'gmail')).toBeVisible();
    await second.close();
  });

  test('postponing every card hides the banner for the session only', async ({ page }) => {
    const account = await signUp(page);
    await page.goto('/dashboard');

    await page.getByTestId('onboarding-later-initial').click();
    await expect(card(page, 'initial')).toBeHidden();
    await page.getByTestId('onboarding-later-gmail').click();
    await expect(card(page, 'gmail')).toBeHidden();
    await page.getByTestId('onboarding-later-whatsapp').click();
    await expect(card(page, 'whatsapp')).toBeHidden();
    await expect(page.getByTestId('onboarding')).toBeHidden();

    await page.goto('/dashboard');
    await expect(page.getByTestId('onboarding')).toBeHidden();

    await page.context().close();
    const second = await page.context().browser().newContext();
    const freshPage = await second.newPage();
    await signIn(freshPage, account.email, account.password);
    await freshPage.goto('/dashboard');
    await expect(freshPage.getByTestId('onboarding')).toBeVisible();
    await second.close();
  });
});
