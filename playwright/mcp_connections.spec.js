const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('MCP connections page', () => {
  test('shows the connection page with address and empty key state', async ({ page }) => {
    await signUp(page);

    await page.goto('/settings/mcp');
    await expect(page.getByRole('heading', { name: 'Conecta tu ChatGPT con Yogasto' })).toBeVisible();
    await expect(page.getByTestId('mcp-endpoint')).toBeVisible();
    await expect(page.locator('#keyStatus')).toContainText('Sin clave');
    await expect(page.locator('#copyPrompt')).toBeDisabled();
  });

  test('creates a key and shows it once', async ({ page }) => {
    await signUp(page);

    await page.goto('/settings/mcp');
    await page.getByRole('button', { name: /Crear clave de conexión/ }).click();

    await expect(page.locator('#keyStatus')).toContainText('Clave activa');
    await expect(page.locator('#reveal')).toBeEnabled();
    await expect(page.locator('#copyKey')).toBeEnabled();
    await expect(page.locator('#copyPrompt')).toBeEnabled();

    const keyValue = await page.locator('#keyValue').textContent();
    expect(keyValue).toMatch(/^ygm_/);

    // Navigate fresh: key should be masked and no longer copyable.
    await page.goto('/settings/mcp');
    await expect(page.locator('#keyStatus')).toContainText('Clave activa');
    await expect(page.locator('#reveal')).toBeDisabled();
    await expect(page.locator('#copyPrompt')).toBeDisabled();
    await expect(page.locator('#keyValue')).toContainText('•');
  });

  test('copy prompt button is disabled without a key', async ({ page }) => {
    await signUp(page);

    await page.goto('/settings/mcp');
    await expect(page.locator('#copyPrompt')).toBeDisabled();
  });
});
