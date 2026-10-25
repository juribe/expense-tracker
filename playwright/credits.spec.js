const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');
const { createCreditCard, createLoan } = require('./helpers/money_sources');

test.describe('Credit intelligence dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  async function createProjectableLoan(page, name, options = {}) {
    await createLoan(page, name, {
      subKind: options.subKind || 'personal',
      principal: '1200000',
      fill: async (page) => {
        const loanPanel = page.locator('[data-kind-panel="loan"]');
        await loanPanel.locator('#money_source_credit_account_attributes_interest_rate').fill('1.0');
        await loanPanel.locator('#money_source_credit_account_attributes_interest_rate_type').selectOption('monthly');
        await loanPanel.locator('#money_source_credit_account_attributes_installment_amount').fill('300000');
        await loanPanel.locator('#money_source_credit_account_attributes_installment_count').fill('5');
        await loanPanel.locator('#money_source_credit_account_attributes_payment_frequency').selectOption('monthly');
        await loanPanel.locator('#money_source_credit_account_attributes_start_date').fill('05/01/2026');
      }
    });
  }

  async function showPath(page, name) {
    const source = page.locator('[data-testid="loan-card"]', { hasText: name }).first();
    const link = source.getByRole('link', { name }).first();
    return link.getAttribute('href');
  }

  async function openCredits(page, sourcePath) {
    await page.goto(sourcePath);
    await page.getByRole('link', { name: 'Ayúdame a ahorrar' }).first().click();
    await expect(page).toHaveURL(new RegExp(`${sourcePath}/credits$`));
  }

  test('revolving credit dashboard renders the projection and quick simulation', async ({ page }) => {
    const name = `Rotativo Créditos-${Date.now()}`;
    await createProjectableLoan(page, name, { subKind: 'revolving' });
    const loanPath = await showPath(page, name);
    await openCredits(page, loanPath);
    const creditsPath = `${loanPath}/credits`;

    await expect(page.getByRole('tab', { name: 'Resumen' })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Cómo ahorrar' })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Escenarios' })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Cronograma' })).toBeVisible();
    await expect(page.getByText('Estado actual')).toBeVisible();
    await expect(page.getByText('Costo futuro')).toBeVisible();
    await expect(page.getByText('Total restante por pagar')).toBeVisible();

    await page.getByRole('tab', { name: 'Cómo ahorrar' }).click();
    await expect(page.locator('[data-testid="credit-quick"]')).toBeVisible();
    await page.locator('#quick_amount').fill('300000');
    await page.getByRole('button', { name: 'Comparar formas de ahorrar' }).click();

    await expect(page.locator('#quick-results')).toBeVisible();
    await expect(page.locator('[data-testid="quick-primary"]')).toBeVisible();
    await expect(page).toHaveURL(new RegExp(`${creditsPath}$`));

    await page.getByRole('tab', { name: 'Cronograma' }).click();
    await expect(page.getByRole('heading', { name: 'Tabla de amortización' })).toBeVisible();
    await expect(page.locator('#credit-tab-cronograma .table-responsive tbody tr').first()).toBeVisible();

    await page.getByRole('link', { name: 'Real vs proyectado' }).click();
    await expect(page).toHaveURL(/view=actual/);
    await expect(page.getByText(/Real \(arriba\) vs proyectado/)).toBeVisible();
  });

  test('quick simulation can be saved as a scenario', async ({ page }) => {
    const name = `Préstamo Escenario-${Date.now()}`;
    await createProjectableLoan(page, name);
    const loanPath = await showPath(page, name);
    await openCredits(page, loanPath);

    await page.getByRole('tab', { name: 'Cómo ahorrar' }).click();
    await page.locator('#quick_amount').fill('300000');
    await page.getByRole('button', { name: 'Comparar formas de ahorrar' }).click();
    await expect(page.locator('#quick-results')).toBeVisible();

    await page.getByRole('button', { name: 'Guardar como escenario' }).first().click();
    await expect(page.getByText('Escenario guardado.')).toBeVisible();

    await page.getByRole('tab', { name: 'Escenarios' }).click();
    await expect(page.getByRole('heading', { name: 'Comparar escenarios' })).toBeVisible();
    await expect(page.getByText(/para terminar antes/).first()).toBeVisible();
  });

  test('reconstruction form builds a projection when the credit lacks data', async ({ page }) => {
    const name = `Préstamo Reconstruir-${Date.now()}`;
    await createLoan(page, name, { subKind: 'personal', principal: '1200000' });
    const loanPath = await showPath(page, name);

    await page.goto(loanPath);
    await page.getByRole('link', { name: 'Ayúdame a ahorrar' }).first().click();

    await expect(page).toHaveURL(new RegExp(`${loanPath}/credits/reconstruct$`));
    await expect(page.getByRole('heading', { name: 'Reconstruir crédito' })).toBeVisible();

    await page.locator('#credit_balance').fill('1200000');
    await page.locator('#credit_interest_rate').fill('1.0');
    await page.locator('#credit_rate_type').selectOption('monthly');
    await page.locator('#credit_installment').fill('300000');
    await page.locator('#credit_original_term').fill('5');
    await page.getByRole('button', { name: 'Calcular proyección' }).click();

    await expect(page).toHaveURL(new RegExp(`${loanPath}/credits$`));
    await expect(page.getByText('Proyección generada correctamente.')).toBeVisible();
    await expect(page.getByText('Estado actual')).toBeVisible();
  });

  test('credit card entry opens the reconstruction form when data is missing', async ({ page }) => {
    const name = `TDC Créditos-${Date.now()}`;
    await createCreditCard(page, name, {
      fill: async (page) => {
        const cardPanel = page.locator('[data-kind-panel="credit_card"]');
        await cardPanel.locator('#money_source_credit_account_attributes_interest_rate').fill('24.5');
        await cardPanel.locator('#money_source_credit_account_attributes_interest_rate_type').selectOption('effective_annual');
      }
    });

    const card = page.locator('[data-testid="credit-card-card"]', { hasText: name }).first();
    const cardPath = await card.getByRole('link', { name }).first().getAttribute('href');

    await page.goto(cardPath);
    await page.getByRole('link', { name: 'Ayúdame a ahorrar' }).first().click();

    await expect(page).toHaveURL(new RegExp(`${cardPath}/credits/reconstruct$`));
    await expect(page.getByRole('heading', { name: 'Reconstruir crédito' })).toBeVisible();
    await expect(page.getByText(name)).toBeVisible();
  });
});
