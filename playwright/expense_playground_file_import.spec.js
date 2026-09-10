const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

test.describe('expense playground – file import', () => {
  const CANDIDATES = [
    {
      amount: 45000,
      currency: 'COP',
      category_id: null,
      category_name: 'Food Delivery',
      description: 'DIDI FOOD',
      merchant: null,
      date: '2026-09-09',
      source: 'playground',
      confidence: 0.92,
      money_source_name: 'Bancolombia Visa ****4821',
      money_source_id: null,
      classification_source: 'cached_ai',
      money_source_source: 'statement_metadata',
      duplicate: false
    },
    {
      amount: 183450,
      currency: 'COP',
      category_id: null,
      category_name: 'Groceries',
      description: 'ÉXITO',
      merchant: null,
      date: '2026-09-09',
      source: 'playground',
      confidence: 0.88,
      money_source_name: 'Bancolombia Visa ****4821',
      money_source_id: null,
      classification_source: 'cached_ai',
      money_source_source: 'statement_metadata',
      duplicate: false
    },
    {
      amount: 45000,
      currency: 'COP',
      category_id: null,
      category_name: 'Food Delivery',
      description: 'DIDI FOOD',
      merchant: null,
      date: '2026-09-09',
      source: 'playground',
      confidence: 0.92,
      money_source_name: 'Bancolombia Visa ****4821',
      money_source_id: null,
      classification_source: 'cached_ai',
      money_source_source: 'statement_metadata',
      duplicate: true
    }
  ];

  const SOURCES = [
    { name: 'Bancolombia Visa ****4821', display_name: 'Bancolombia Visa ****4821' }
  ];

  function mockProcessFile(page, payload, status = 200) {
    page.route(/\/expense-playground\/process_file/, (route) => {
      route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(payload) });
    });
  }

  function mockBatchCreate(page, payload, status = 200) {
    page.route(/\/expense-playground\/batch_create/, (route) => {
      route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(payload) });
    });
  }

  function okFilePayload(overrides = {}) {
    return Object.assign({
      ok: true,
      candidates: CANDIDATES,
      sources: SOURCES,
      errors: [],
      warnings: [],
      duplicates: CANDIDATES.filter(c => c.duplicate).length,
      step_results: {
        extraction: { engine: 'csv', detected_count: 3 },
        normalization: { warnings: [] },
        enrichment: { reused_classifications: 2, reused_sources: 3, ai_calls: 0 }
      }
    }, overrides);
  }

  // ---- Tab switching ----

  test('file tab shows the file upload panel', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');

    await expect(page.getByTestId('panel-file')).toBeHidden();

    await page.getByTestId('tab-file').click();

    await expect(page.getByTestId('panel-file')).toBeVisible();
    await expect(page.getByTestId('playground-file-dropzone')).toBeVisible();
    await expect(page.getByTestId('playground-statement-file-input')).toBeAttached();
  });

  // ---- File selection – CSV ----

  test('selecting a CSV file shows the filename and hides the PDF password field', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await expect(page.getByTestId('playground-file-name')).toContainText('statement.csv');
    await expect(page.getByTestId('playground-pdf-password')).toBeHidden();
  });

  // ---- File selection – PDF shows password field ----

  test('selecting a PDF file shows the PDF password input', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const pdfBuffer = Buffer.from('%PDF-1.4 fake pdf content');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.pdf',
      mimeType: 'application/pdf',
      buffer: pdfBuffer
    });

    await expect(page.getByTestId('playground-file-name')).toContainText('statement.pdf');
    await expect(page.getByTestId('playground-pdf-password')).toBeVisible();
  });

  // ---- Unsupported file type ----

  test('selecting an unsupported file type shows an error', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const txtBuffer = Buffer.from('not a supported file');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'data.txt',
      mimeType: 'text/plain',
      buffer: txtBuffer
    });

    await expect(page.getByTestId('playground-result-errors')).toBeVisible();
    await expect(page.getByTestId('playground-result-errors')).toContainText('Formato de archivo no soportado');
  });

  // ---- Remove file ----

  test('clicking remove clears the selected file', async ({ page }) => {
    await signUp(page);
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,TEST,1000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'test.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await expect(page.getByTestId('playground-file-name')).toContainText('test.csv');

    await page.getByTestId('playground-remove-file').click();

    await expect(page.getByTestId('playground-file-name')).toHaveText('');
  });

  // ---- Processing shows candidates ----

  test('processing a file shows extracted candidates in the preview table', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, okFilePayload());
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n2026-09-09,ÉXITO,183450\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-file-result')).toBeVisible();
    await expect(page.getByTestId('playground-file-count')).toContainText('3 transactions');
    await expect(page.getByTestId('file-candidate-row')).toHaveCount(3);
  });

  // ---- Money sources are displayed ----

  test('detected money sources are shown above the candidate table', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, okFilePayload());
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-file-sources')).toBeVisible();
    await expect(page.getByTestId('playground-file-sources-list')).toContainText('Bancolombia Visa ****4821');
  });

  // ---- Duplicate badges ----

  test('duplicate transactions show a warning badge', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, okFilePayload());
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-file-result')).toBeVisible();

    const duplicateRows = page.getByTestId('file-candidate-duplicate');
    await expect(duplicateRows.first()).toBeVisible();

    const readyRows = page.getByTestId('file-candidate-ready');
    await expect(readyRows.first()).toBeVisible();
  });

  // ---- Classification & money source metadata ----

  test('each row displays classification and money source metadata', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, okFilePayload());
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-file-result')).toBeVisible();

    const firstRow = page.getByTestId('file-candidate-row').first();
    await expect(firstRow).toContainText('DIDI FOOD');
    await expect(firstRow).toContainText('Food Delivery');
    await expect(firstRow).toContainText('Bancolombia Visa ****4821');
    await expect(firstRow).toContainText('cached_ai');
    await expect(firstRow).toContainText('statement_metadata');
  });

  // ---- Batch create success ----

  test('clicking create all persists expenses and shows success', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, okFilePayload());
    mockBatchCreate(page, {
      ok: true,
      created: [
        { id: 1, description: 'DIDI FOOD', amount: 45000 },
        { id: 2, description: 'ÉXITO', amount: 183450 },
        { id: 3, description: 'DIDI FOOD', amount: 45000 }
      ],
      errors: []
    });
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();
    await expect(page.getByTestId('playground-file-result')).toBeVisible();

    await page.getByTestId('playground-file-create-button').click();

    await expect(page.getByTestId('playground-file-success')).toBeVisible();
    await expect(page.getByTestId('playground-file-success')).toContainText('3');
    await expect(page.getByTestId('playground-file-create-button')).toBeHidden();
  });

  // ---- Batch create partial failure ----

  test('batch create errors are displayed to the user', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, okFilePayload());
    mockBatchCreate(page, {
      ok: false,
      created: [],
      errors: [{ index: 0, errors: ['Amount is required'] }]
    }, 422);
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();
    await expect(page.getByTestId('playground-file-result')).toBeVisible();

    await page.getByTestId('playground-file-create-button').click();

    await expect(page.getByTestId('playground-result-errors')).toBeVisible();
    await expect(page.getByTestId('playground-result-errors')).toContainText('Row 0');
  });

  // ---- File processing error ----

  test('server errors during file processing are displayed', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, {
      ok: false,
      candidates: [],
      sources: [],
      errors: ['Could not parse this file. The format is not supported.'],
      warnings: []
    }, 422);
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n2026-09-09,DIDI FOOD,45000\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'statement.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-file-errors')).toBeVisible();
    await expect(page.getByTestId('playground-file-errors')).toContainText('Could not parse');
  });

  // ---- No transactions extracted ----

  test('file with no extractable transactions shows a message', async ({ page }) => {
    await signUp(page);
    mockProcessFile(page, {
      ok: true,
      candidates: [],
      sources: [],
      errors: [],
      warnings: []
    });
    await page.goto('/expense-playground');
    await page.getByTestId('tab-file').click();

    const csvBuffer = Buffer.from('Date,Description,Amount\n');
    await page.getByTestId('playground-statement-file-input').setInputFiles({
      name: 'empty.csv',
      mimeType: 'text/csv',
      buffer: csvBuffer
    });

    await page.getByTestId('playground-process-button').click();

    await expect(page.getByTestId('playground-file-result')).toBeVisible();
    await expect(page.getByTestId('playground-file-create-button')).toBeHidden();
  });
});
