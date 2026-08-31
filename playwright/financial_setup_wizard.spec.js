const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('Hybrid financial setup wizard', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('user can set up a source manually, skip steps, and complete onboarding', async ({ page }) => {
    await page.goto('/financial_setup');

    // Entry screen
    await expect(page.getByRole('heading', { name: 'Configura tus finanzas' })).toBeVisible();
    await page.getByRole('button', { name: 'Comenzar configuración' }).click();

    // Accounts: choose manual
    await expect(page.getByText('¿Cómo quieres agregar tus cuentas?')).toBeVisible();
    await page.locator('input[name="choice"][value="manual"]').check({ force: true });
    await page.getByRole('button', { name: 'Continuar' }).click();

    // Manual entry
    const name = `Ahorros Wizard-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(name);
    await page.locator('input[name="sources[0][bank]"]').fill('Bancolombia');
    await page.locator('input[name="sources[0][balance]"]').fill('5420000');
    await page.getByRole('button', { name: 'Continuar' }).click();

    // Credit cards: skip
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();
    await page.locator('input[name="choice"][value="skip"]').check({ force: true });
    await page.getByRole('button', { name: 'Continuar' }).click();

    // Loans: skip
    await expect(page.getByText('¿Cómo quieres agregar tus préstamos?')).toBeVisible();
    await page.locator('input[name="choice"][value="skip"]').check({ force: true });
    await page.getByRole('button', { name: 'Continuar' }).click();;

    // Final review
    await expect(page.getByText('1 fuente financiera configurada')).toBeVisible();
    await expect(page.getByText('1 Cuenta')).toBeVisible();
    await page.getByText('1 Cuenta').click();
    await expect(page.getByText(name)).toBeVisible();

    // Complete setup
    await page.getByRole('button', { name: 'Finalizar configuración' }).click();
    await expect(page.getByRole('heading', { name: 'Tus finanzas están listas' })).toBeVisible();
    await expect(page.getByText('1 fuente financiera configurada')).toBeVisible();

    // Source persisted
    await page.getByRole('link', { name: /Ir al panel/ }).click();
    await page.goto('/money_sources');
    await expect(page.getByText(name)).toBeVisible();
  });

  test('an in-progress setup shows a resume banner on money sources', async ({ page }) => {
    await page.goto('/financial_setup');
    await page.getByRole('button', { name: 'Comenzar configuración' }).click();
    await page.locator('input[name="choice"][value="skip"]').check({ force: true });
    await page.getByRole('button', { name: 'Continuar' }).click();
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();

    // Leave and return later
    await page.goto('/dashboard');
    await page.goto('/money_sources');
    await expect(page.getByTestId('unfinished-setup-banner')).toBeVisible();
    await expect(page.getByRole('link', { name: 'Retomar configuración' })).toBeVisible();
  });
});