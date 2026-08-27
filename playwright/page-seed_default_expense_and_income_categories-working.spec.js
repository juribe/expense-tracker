const { test, expect } = require('@playwright/test');

test.describe("Seed Default Expense and Income Categories pages are working", () => {
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
  
  test("/incomes is working", async ({ page }) => {
    const response = await page.goto("/incomes");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });

});
