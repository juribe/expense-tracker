const { test, expect } = require('@playwright/test');

test.describe("default and custom categories pages are working", () => {
  test("/categories is working", async ({ page }) => {
    const response = await page.goto("/categories");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/categories/new is working", async ({ page }) => {
    const response = await page.goto("/categories/new");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/categories/1/edit is working", async ({ page }) => {
    const response = await page.goto("/categories/1/edit");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/categories/1 is working", async ({ page }) => {
    const response = await page.goto("/categories/1");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });

});
