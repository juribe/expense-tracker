const { test, expect } = require('@playwright/test');

test.describe("Bulk Update Expense Category and Money Source pages are working", () => {
  test("/expenses is working", async ({ page }) => {
    const response = await page.goto("/expenses");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/expenses/new is working", async ({ page }) => {
    const response = await page.goto("/expenses/new");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/expenses/1/edit is working", async ({ page }) => {
    const response = await page.goto("/expenses/1/edit");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/expenses/1 is working", async ({ page }) => {
    const response = await page.goto("/expenses/1");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/money_sources is working", async ({ page }) => {
    const response = await page.goto("/money_sources");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });

});
