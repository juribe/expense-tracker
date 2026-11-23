const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('simple email forwarding wizard', () => {
  test('explains forwarding first and then builds a copyable provider rule', async ({ page }) => {
    await signUp(page, { moneyTrackingMode: 'simple' });

    await page.goto('/settings/email');
    await page.getByTestId('open-forwarding-rule-wizard').click();

    const wizard = page.getByTestId('forwarding-rule-wizard');
    await expect(wizard).toBeVisible();

    const explainStep = page.getByTestId('forwarding-wizard-explain-step');
    const ruleStep = page.getByTestId('forwarding-wizard-rule-step');

    await expect(explainStep).toBeVisible();
    await expect(explainStep).toContainText('regla de reenvío');
    await expect(ruleStep).toBeHidden();

    await page.getByTestId('forwarding-wizard-next').click();

    await expect(ruleStep).toBeVisible();
    await expect(explainStep).toBeHidden();

    await page.locator('#forwarding_rule_senders').fill('notifications@bank.com\nbank.com');
    await page.locator('#forwarding_rule_subjects').fill('compra, pago');

    await expect(page.locator('#forwarding_rule_query')).toHaveText(
      'from:(notifications@bank.com OR bank.com) subject:("compra" OR "pago")'
    );
    await expect(page.locator('#forwarding_rule_summary')).toContainText('notifications@bank.com');
    await expect(page.locator('[data-provider-panel=gmail]')).toBeVisible();

    await page.locator('#forwarding_rule_provider').selectOption('outlook');
    await expect(page.locator('[data-provider-panel=gmail]')).toBeHidden();
    await expect(page.locator('[data-provider-panel=outlook]')).toBeVisible();
    await expect(page.locator('[data-provider-panel=outlook]')).toContainText('Outlook');

    await page.locator('#forwarding_rule_provider').selectOption('other');
    await expect(page.locator('[data-provider-panel=other]')).toBeVisible();
    await expect(wizard).not.toContainText('Money Source');
    await expect(wizard).not.toContainText('Cuenta de ahorro');

    await page.getByTestId('forwarding-wizard-back').click();
    await expect(explainStep).toBeVisible();
  });
});
