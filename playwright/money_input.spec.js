const { test, expect } = require('@playwright/test');
const { signUp, createCategory } = require('./helpers/auth');

// es-CO money parsing: comma = decimals, dot = thousands. But a final dot
// group of 1-2 digits means the user typed dot decimals ("5.50" — the rule
// decimalParts/sanitizeValue already implement); the live formatter must
// respect it instead of swallowing the dot ("550"/$550 regression).
test.describe('money input parsing rules', () => {
  test('a final 1-2 digit dot group is decimals ("5.50" stays $5,50)', async ({ page }) => {
    await signUp(page);
    await page.goto('/expenses/new');

    const rules = await page.evaluate(() => ({
      dotDecimals: window.MoneyInputs.formatValue('5.50'),
      twoDotGroup: window.MoneyInputs.formatValue('12.34'),
      bothParts: window.MoneyInputs.formatValue('1234.56'),
      sanitizeKeepsValue: window.MoneyInputs.sanitizeValue('5.50'),
      blurred: (() => {
        const input = document.querySelector('#expense_amount');
        input.value = '5.50';
        window.MoneyInputs.formatField(input, true);
        return input.value;
      })()
    }));

    expect(rules.dotDecimals).toBe('5,50');
    expect(rules.twoDotGroup).toBe('12,34');
    expect(rules.bothParts).toBe('1.234,56');
    expect(rules.sanitizeKeepsValue).toBe('5.50');
    expect(rules.blurred).toBe('5,50');
  });

  test('a 3-digit dot group is still thousands ("1.234" stays 1,234)', async ({ page }) => {
    await signUp(page);
    await page.goto('/expenses/new');

    const rules = await page.evaluate(() => ({
      thousands: window.MoneyInputs.formatValue('1.234'),
      thousandsValue: window.MoneyInputs.sanitizeValue('1.234'),
      commaDecimals: window.MoneyInputs.formatValue('1.234,50'),
      commaSanitized: window.MoneyInputs.sanitizeValue('1.234,50')
    }));

    expect(rules.thousands).toBe('1.234');
    expect(rules.thousandsValue).toBe('1234');
    expect(rules.commaDecimals).toBe('1.234,50');
    expect(rules.commaSanitized).toBe('1234.50');
  });

  test('an expense of 5.50 is stored as 5.50 so amount rules can match it', async ({ page }) => {
    await signUp(page);
    await createCategory(page, `Food-${Date.now()}`);

    await page.goto('/expenses/new');
    await page.locator('#expense_amount').fill('5.50');
    await page.locator('#expense_description').fill('Café barra');
    await page.getByRole('button', { name: 'Guardar' }).click();

    await expect(page).toHaveURL(/\/expenses/);
    await expect(page.getByText('El gasto se creó correctamente.')).toBeVisible();
    await expect(page.locator('#expenseTable td.desc-cell')).toHaveText('Café barra');

    // The index table rounds to whole pesos (COP, precision 0); the edit form
    // field strips trailing zeros ("5,5"), so it proves the stored amount is
    // 5.50, not 550.
    await page.locator('#expenseTable tr', { hasText: 'Café barra' })
              .getByRole('link', { name: /Editar/i }).click();
    await expect(page.locator('#expense_amount')).toHaveValue('5,5');
  });
});
