const { test, expect } = require("@playwright/test");

test.describe("installable PWA shell", () => {
  test("links an installable manifest, registers the worker and keeps private data out of the cache", async ({ page, context }) => {
    await page.goto("/", { waitUntil: "networkidle" });

    await expect(page.locator("link[rel='manifest']")).toHaveAttribute("href", "/manifest");
    await expect(page.locator("meta[name='apple-mobile-web-app-title']")).toHaveAttribute("content", "Yogasto");
    await expect(page.locator("meta[name='viewport']")).toHaveAttribute("content", /viewport-fit=cover/);

    const manifestResponse = await page.request.get("/manifest");
    expect(manifestResponse.ok()).toBeTruthy();

    const manifest = await manifestResponse.json();
    expect(manifest.display).toBe("standalone");
    expect(manifest.start_url).toBe("/");
    expect(manifest.scope).toBe("/");
    expect(manifest.orientation).toBe("portrait");
    expect(manifest.icons.map((icon) => icon.sizes).sort()).toEqual(["192x192", "192x192", "512x512", "512x512"]);
    expect(manifest.icons.filter((icon) => icon.purpose === "maskable")).toHaveLength(2);

    const worker = await page.evaluate(async () => {
      const registration = await navigator.serviceWorker.ready;
      if (!navigator.serviceWorker.controller) {
        await new Promise((resolve) => {
          navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true });
          setTimeout(resolve, 5000);
        });
      }
      return { scope: registration.scope, active: Boolean(registration.active), controlled: Boolean(navigator.serviceWorker.controller) };
    });

    expect(worker.active).toBeTruthy();
    expect(worker.controlled).toBeTruthy();

    const cachedPaths = await page.evaluate(async () => {
      const paths = [];
      for (const name of await caches.keys()) {
        const cache = await caches.open(name);
        for (const request of await cache.keys()) paths.push(new URL(request.url).pathname);
      }
      return paths;
    });

    expect(cachedPaths.length).toBeGreaterThan(0);
    for (const path of cachedPaths) {
      expect(path.startsWith("/pwa/") || path === "/offline.html" || path === "/offline.css").toBeTruthy();
    }

    await context.setOffline(true);
    await page.goto("/precios", { waitUntil: "domcontentloaded" }).catch(() => {});
    await expect(page.getByRole("heading", { name: "Sin conexión" })).toBeVisible();
  });
});
