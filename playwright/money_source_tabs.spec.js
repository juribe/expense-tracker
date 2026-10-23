const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('Money source show page tabs', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  async function createRevolvingLoan(page, name) {
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('loan');
    await page.locator('#money_source_sub_kind').selectOption('revolving');
    await page.locator('#money_source_credit_account_attributes_principal_amount').fill('5000000');
    await page.locator('.card form button[type="submit"], .card form input[type="submit"]').first().click();
    await expect(page).toHaveURL(/\/money_sources\/loans$/);
  }

  async function openShowPage(page, name) {
    const card = page.locator('[data-testid="loan-card"]', { hasText: name }).first();
    const editHref = await card.locator('a[href$="/edit"]').getAttribute('href');
    await page.goto(editHref.replace(/\/edit$/, ''));
  }

  test('debt show page renders tabs and switches panes', async ({ page }) => {
    const name = `Rotativo Tabs-${Date.now()}`;
    await createRevolvingLoan(page, name);
    await openShowPage(page, name);

    await expect(page.getByRole('heading', { name })).toBeVisible();

    const summary = page.locator('[data-tab-slug="resumen"]');
    const payments = page.locator('[data-tab-slug="pagos"]');
    const extras = page.locator('[data-tab-slug="abonos"]');
    await expect(summary).toBeVisible();
    await expect(payments).toBeVisible();
    await expect(extras).toBeVisible();
    await expect(summary).toHaveClass(/active/);

    await expect(page.locator('#source-tab-pagos')).not.toBeVisible();

    await payments.click();
    await expect(payments).toHaveClass(/active/);
    await expect(page.getByRole('heading', { name: 'Pagos aplicados' })).toBeVisible();

    await extras.click();
    await expect(extras).toHaveClass(/active/);
    await expect(page.getByRole('heading', { name: 'Abonos extraordinarios' })).toBeVisible();
  });

  test('selected tab is restored after a reload', async ({ page }) => {
    const name = `Rotativo Persist-${Date.now()}`;
    await createRevolvingLoan(page, name);
    await openShowPage(page, name);

    await page.locator('[data-tab-slug="pagos"]').click();
    await expect(page.locator('[data-tab-slug="pagos"]')).toHaveClass(/active/);

    await page.reload();
    await expect(page.locator('[data-tab-slug="pagos"]')).toHaveClass(/active/);
    await expect(page.locator('#source-tab-pagos')).toBeVisible();
  });

  test('credit card show page exposes the recognition tab', async ({ page }) => {
    const name = `TDC Tabs-${Date.now()}`;
    await page.goto('/money_sources/new');
    await page.locator('#money_source_name').fill(name);
    await page.locator('#money_source_kind').selectOption('credit_card');
    await page.locator('#money_source_credit_account_attributes_card_last_four').fill('1234');
    await page.locator('#money_source_credit_account_attributes_credit_limit').fill('20000000');
    await page.locator('.card form button[type="submit"], .card form input[type="submit"]').first().click();
    await expect(page).toHaveURL(/\/money_sources\/credit_cards$/);

    const card = page.locator('[data-testid="credit-card-card"]', { hasText: name }).first();
    const editHref = await card.locator('a[href$="/edit"]').getAttribute('href');
    await page.goto(editHref.replace(/\/edit$/, ''));

    await expect(page.locator('[data-tab-slug="reconocimiento"]')).toBeVisible();
    await page.locator('[data-tab-slug="reconocimiento"]').click();
    await expect(page.getByRole('heading', { name: 'Reconocimiento' })).toBeVisible();
  });
});
