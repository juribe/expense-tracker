const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('Hybrid financial setup wizard', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  async function startWizard(page) {
    await page.goto('/financial_setup');
    await expect(page.getByRole('heading', { name: 'Configura tus finanzas' })).toBeVisible();
    await page.getByRole('button', { name: 'Comenzar configuración' }).click();
  }

  async function choose(page, title) {
    await page.locator('label.choice-card', { hasText: title }).click();
  }

  async function skipCash(page) {
    await expect(page.getByText('¿Cómo quieres agregar tus efectivo?')).toBeVisible();
    await choose(page, 'Omitir por ahora');
  }

  async function skipSteps(page) {
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();
    await choose(page, 'Omitir por ahora');
    await expect(page.getByText('¿Cómo quieres agregar tus préstamos?')).toBeVisible();
    await choose(page, 'Omitir por ahora');
  }

  test('user can set up a source manually, skip steps, and complete onboarding', async ({ page }) => {
    await startWizard(page);
    await skipCash(page);

    // Accounts: choose manual
    await expect(page.getByText('¿Cómo quieres agregar tus cuentas?')).toBeVisible();
    await choose(page, 'Agregar manualmente');

    // Manual entry
    const name = `Ahorros Wizard-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(name);
    await page.locator('input[name="sources[0][bank]"]').fill('Bancolombia');
    await page.locator('input[name="sources[0][balance]"]').fill('5420000');
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();

    // Credit cards & loans: skip
    await skipSteps(page);

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

  test('user can add multiple sources of each kind manually and see them in final review', async ({ page }) => {
    await startWizard(page);
    await skipCash(page);

    // Accounts: add two manually in a single step
    await expect(page.getByText('¿Cómo quieres agregar tus cuentas?')).toBeVisible();
    await choose(page, 'Agregar manualmente');

    const accountA = `Ahorros A-${Date.now()}`;
    const accountB = `Ahorros B-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(accountA);
    await page.locator('input[name="sources[0][bank]"]').fill('Bancolombia');
    await page.locator('input[name="sources[0][balance]"]').fill('5420000');

    await page.getByRole('button', { name: 'Agregar otra' }).click();
    await page.locator('input[name="sources[1][name]"]').fill(accountB);
    await page.locator('input[name="sources[1][bank]"]').fill('Davivienda');
    await page.locator('input[name="sources[1][balance]"]').fill('2180000');
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();

    // Credit cards: add one manually
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();
    await choose(page, 'Agregar manualmente');

    const card = `Visa Oro-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(card);
    await page.locator('input[name="sources[0][bank]"]').fill('Bancolombia');
    await page.locator('input[name="sources[0][identifier]"]').fill('1234');
    await page.locator('input[name="sources[0][balance]"]').fill('1200000');
    await page.locator('input[name="sources[0][credit_limit]"]').fill('8000000');
    await page.locator('input[name="sources[0][interest_rate]"]').fill('12');
    await page.locator('select[name="sources[0][interest_rate_type]"]').selectOption('effective_annual');
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();

    // Loans: add one manually
    await expect(page.getByText('¿Cómo quieres agregar tus préstamos?')).toBeVisible();
    await choose(page, 'Agregar manualmente');

    const loan = `Hipoteca-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(loan);
    await page.locator('input[name="sources[0][bank]"]').fill('Banco de Bogotá');
    await page.locator('input[name="sources[0][principal_amount]"]').fill('450000000');
    await page.locator('input[name="sources[0][outstanding_balance]"]').fill('450000000');
    await page.locator('input[name="sources[0][monthly_payment]"]').fill('3100000');
    await page.locator('input[name="sources[0][installment_count]"]').fill('72');
    await page.locator('select[name="sources[0][interest_rate_type]"]').selectOption('effective_annual');
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();

    // Final review: summary counts across all kinds
    await expect(page.getByText('2 Cuentas')).toBeVisible();
    await expect(page.getByText('1 Tarjeta de Crédito')).toBeVisible();
    await expect(page.getByText('1 Préstamo')).toBeVisible();
    await expect(page.getByText('4 fuentes financieras configuradas')).toBeVisible();

    // Complete setup and confirm persistence of all four sources
    await page.getByRole('button', { name: 'Finalizar configuración' }).click();
    await expect(page.getByRole('heading', { name: 'Tus finanzas están listas' })).toBeVisible();
    await page.getByRole('link', { name: /Ir al panel/ }).click();
    await page.goto('/money_sources');
    for (const source of [ accountA, accountB, card, loan ]) {
      await expect(page.getByText(source)).toBeVisible();
    }
  });

  test('user can save a step, dismiss the setup, and resume later without losing progress', async ({ page }) => {
    await startWizard(page);
    await skipCash(page);

    // Save one manual account (submitting advances to the credit cards step)
    await expect(page.getByText('¿Cómo quieres agregar tus cuentas?')).toBeVisible();
    await choose(page, 'Agregar manualmente');
    const name = `Corriente Dismiss-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(name);
    await page.locator('input[name="sources[0][bank]"]').fill('Bancolombia');
    await page.locator('input[name="sources[0][balance]"]').fill('100000');
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();

    // Leave from the credit cards step
    await page.getByRole('link', { name: 'Continuar después' }).click();

    await page.goto('/money_sources');
    await expect(page.getByTestId('unfinished-setup-banner')).toBeVisible();
    await page.getByRole('link', { name: 'Retomar configuración' }).click();

    // Resume continues at the saved current step (credit cards)
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();

    // Navigate back to the accounts step and confirm the saved draft is preserved
    await page.getByRole('link', { name: 'Atrás' }).click();
    await choose(page, 'Agregar manualmente');
    await expect(page.locator('input[name="sources[0][name]"]')).toHaveValue(name);
  });

  test('user can go back to a previous step and edit the saved information', async ({ page }) => {
    await startWizard(page);
    await skipCash(page);

    await expect(page.getByText('¿Cómo quieres agregar tus cuentas?')).toBeVisible();
    await choose(page, 'Agregar manualmente');

    const original = `Ahorros Original-${Date.now()}`;
    await page.locator('input[name="sources[0][name]"]').fill(original);
    await page.locator('input[name="sources[0][bank]"]').fill('Bancolombia');
    await page.locator('input[name="sources[0][balance]"]').fill('100000');
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();

    // Skip through the remaining steps to reach review
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();
    await choose(page, 'Omitir por ahora');
    await expect(page.getByText('¿Cómo quieres agregar tus préstamos?')).toBeVisible();
    await choose(page, 'Omitir por ahora');

    // Review shows the saved account
    await expect(page.getByText('1 Cuenta')).toBeVisible();

    // "Volver a editar" returns to the previous source step (loans)
    await page.getByRole('link', { name: 'Volver a editar' }).click();
    await expect(page.getByText('¿Cómo quieres agregar tus préstamos?')).toBeVisible();

    // Step back through credit cards to accounts
    await page.getByRole('link', { name: 'Atrás' }).click();
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();
    await page.getByRole('link', { name: 'Atrás' }).click();
    await expect(page.getByText('¿Cómo quieres agregar tus cuentas?')).toBeVisible();

    // Re-enter the manual accounts screen and edit the saved value
    await choose(page, 'Agregar manualmente');

    const edited = `${original} editado`;
    await page.locator('input[name="sources[0][name]"]').fill(edited);
    await page.getByRole('button', { name: 'Continuar', exact: true }).click();

    // Skip through again and confirm the edited name appears in review
    await expect(page.getByText('¿Cómo quieres agregar tus tarjetas de crédito?')).toBeVisible();
    await choose(page, 'Omitir por ahora');
    await expect(page.getByText('¿Cómo quieres agregar tus préstamos?')).toBeVisible();
    await choose(page, 'Omitir por ahora');

    await expect(page.getByText('1 fuente financiera configurada')).toBeVisible();
    await page.getByText('1 Cuenta').click();
    await expect(page.getByText(edited)).toBeVisible();
    await expect(page.getByText(original, { exact: true })).toBeHidden();
  });
});