const { test, expect } = require('@playwright/test');

test.describe("ClickUp Task: Support Monthly Income and Payments pages are working", () => {
  test("/monthly_reports is working", async ({ page }) => {
    const response = await page.goto("/monthly_reports");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });
  
  test("/monthly_reports/1 is working", async ({ page }) => {
    const response = await page.goto("/monthly_reports/1");
    expect(response && response.ok()).toBeTruthy();
    await expect(page.locator('body')).toBeVisible();
  });

});
