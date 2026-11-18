const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

test.describe('Análisis section', () => {
  test.beforeEach(async ({ page }) => {
    await signUp(page);
  });

  test('financial chat renders its empty conversation and composer', async ({ page }) => {
    await page.goto('/financial_chat');

    await expect(page.locator('#financialChat')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Chat Financiero' })).toBeVisible();
    await expect(page.getByTestId('chat-messages')).toBeVisible();
    await expect(page.getByText('¿Cómo puedo ayudarte con tus finanzas?')).toBeVisible();
    await expect(page.locator('#chatComposer')).toBeVisible();

    const input = page.locator('#chatInput');
    const send = page.locator('#chatSend');
    await expect(send).toBeDisabled();
    await input.fill('Hola');
    await expect(send).toBeEnabled();
    await input.fill('');
    await expect(send).toBeDisabled();
  });

  test('debt capacity renders its summary and switches every tab', async ({ page }) => {
    await page.goto('/debt_capacity');

    await expect(page.getByRole('heading', { name: 'Deudas y capacidad de endeudamiento' })).toBeVisible();
    await expect(page.getByTestId('debt-capacity-page')).toBeVisible();
    await expect(page.getByTestId('debt-capacity-summary')).toBeVisible();
    await expect(page.locator('#dc-capacity')).toBeVisible();

    await page.getByRole('tab', { name: 'Obligaciones' }).click();
    await expect(page.locator('#dc-obligations')).toBeVisible();

    await page.getByRole('tab', { name: 'Simulador' }).click();
    await expect(page.locator('#dc-simulator')).toBeVisible();
    await expect(page.getByTestId('debt-capacity-comparison')).toBeVisible();

    await page.getByRole('tab', { name: 'Recomendaciones' }).click();
    await expect(page.getByTestId('debt-capacity-recommendations')).toBeVisible();
  });

  test('savings opportunities renders its empty state and refresh action', async ({ page }) => {
    await page.goto('/savings_opportunities');

    await expect(page.locator('[data-so-page]')).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Oportunidades de ahorro' })).toBeVisible();
    await expect(page.getByRole('button', { name: /Actualizar análisis/ })).toBeVisible();
    await expect(page.getByText('Aún no hay movimientos suficientes')).toBeVisible();
    await expect(page.getByText('Cuando registres gastos, analizaremos tus patrones')).toBeVisible();
  });

  test('financial habits renders the analysis landing and empty state', async ({ page }) => {
    await page.goto('/financial_habits');

    await expect(page.getByRole('heading', { name: 'Descubre tus hábitos financieros' })).toBeVisible();
    await expect(page.getByText('Análisis personalizado')).toBeVisible();
    await expect(page.getByText('Hay cosas sobre tu dinero que quizás no habías notado.')).toBeVisible();
    await expect(page.getByText('Estamos conociendo tus hábitos financieros')).toBeVisible();
  });

  test('category insights renders its stats, filters and empty list', async ({ page }) => {
    await page.goto('/category_insights');

    await expect(page.getByRole('heading', { name: 'Ahorro por categoría' })).toBeVisible();
    await expect(page.getByTestId('stat-analyzed')).toBeVisible();
    await expect(page.getByTestId('stat-potential')).toBeVisible();
    await expect(page.getByTestId('stat-limited')).toBeVisible();
    await expect(page.locator('[data-category-insights-search]')).toBeVisible();
    await expect(page.locator('[data-category-insights-sort]')).toBeVisible();
    await expect(page.getByRole('button', { name: /Todas/ })).toBeVisible();
    await expect(
      page.locator('[data-category-insights-item]:visible, [data-category-insights-empty]:visible').first()
    ).toBeVisible();
  });

  test('category insight detail renders its analysis and tips', async ({ page }) => {
    const category = `Análisis Cat-${Date.now()}`;
    await createCategory(page, category);
    const categoryId = new URL(page.url()).pathname.split('/').pop();

    await page.goto(`/category_insights/${categoryId}`);

    await expect(page.getByTestId('category-insight-header')).toBeVisible();
    await expect(page.getByRole('heading', { name: category })).toBeVisible();
    await expect(page.getByTestId('category-insight-analysis')).toBeVisible();
    await expect(page.getByTestId('category-insight-potential')).toBeVisible();
    await expect(page.getByTestId('metric-average')).toBeVisible();
    await expect(page.getByTestId('metric-reduction')).toBeVisible();
    await expect(page.getByTestId('metric-savings')).toBeVisible();
    await expect(page.getByTestId('metric-current')).toBeVisible();
    await expect(page.getByTestId('category-insight-missing-history')).toBeVisible();
    await expect(page.getByTestId('category-insight-tips')).toBeVisible();
  });
});
