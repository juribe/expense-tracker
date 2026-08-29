const { test, expect } = require('@playwright/test');

test.describe("migrate database to postgresql pages are working", () => {
  test("/ is working", async ({ page }) => {
    const response = await page.goto("/");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });

});
