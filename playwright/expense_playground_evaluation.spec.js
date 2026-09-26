const { test, expect } = require('@playwright/test');
const { signUp } = require('./helpers/auth');

// AI Evaluation mode inside the existing Expense Playground. Tests mock the
// evaluation API (same approach as the rest of the playground specs: the real
// server would enqueue SolidQueue jobs and hit live AI providers, which a
// focused UI test must never do). Scenarios covered:
//   - the Evaluation tab exposes the dataset/provider/model form
//   - starting a run polls the run and renders aggregated metrics
//   - backend dataset validation errors are surfaced
//   - the form blocks submission without a model
//   - failed cases are searchable and filterable by status
//   - the model-comparison table lists completed runs for the same dataset
test.describe('expense playground – AI evaluation', () => {
  const RUN_ID = 42;
  const DATASET = 'gastos.csv';
  const MODEL = 'mistral/mistral-small-latest';
  const PROMPT_VERSION = 'expense-extraction-v1';

  const COMPLETED_METRICS = {
    total_cases: 1000,
    passed_cases: 942,
    failed_cases: 58,
    errored: 3,
    pending: 0,
    overall_accuracy: 0.942,
    accuracy: 0.942,
    full_record_accuracy: 0.942,
    json_valid: 990,
    json_validity: 0.99,
    average_latency: 1.2,
    total_input_tokens: 118000,
    total_output_tokens: 41000,
    input_cost: 0.08,
    output_cost: 0.10,
    cost: 0.18,
    total_cost: 0.18,
    fields: {
      amount: { compared: 1000, passed: 1000 },
      date: { compared: 1000, passed: 962 }
    },
    field_accuracy: {
      intent: 0.98,
      amount: 1.0,
      date: 0.96,
      activity: 0.95,
      category: 0.95,
      subcategory: 0.9,
      money_source: 0.91,
      currency: 0.99
    },
    amount_accuracy: 1.0,
    date_accuracy: 0.96
  };

  const RUNNING_METRICS = {
    total_cases: 1000,
    passed_cases: 471,
    failed_cases: 29,
    json_validity: 0.5,
    total_cost: 0.09,
    average_latency: 1.1,
    fields: { amount: { compared: 500, passed: 498 } },
    field_accuracy: {}
  };

  function run(overrides = {}) {
    return Object.assign({
      id: RUN_ID,
      dataset_name: DATASET,
      dataset_version: 'sha1',
      provider: 'openrouter',
      model: MODEL,
      prompt_version: PROMPT_VERSION,
      status: 'running',
      total_cases: 1000,
      progress: 0.5,
      created_at: '2026-09-13T10:00:00Z',
      started_at: '2026-09-13T10:00:00Z',
      completed_at: null,
      metrics: {}
    }, overrides);
  }

  const RUNNING = run({ status: 'running', progress: 0.5, metrics: RUNNING_METRICS });
  const COMPLETED = run({ status: 'completed', progress: 1, completed_at: '2026-09-13T10:05:00Z', metrics: COMPLETED_METRICS });

  const FAILED_CASE = {
    id: 101,
    row_number: 23,
    status: 'failed',
    message: 'ayer gasté 80 lucas en panadería',
    expected_json: JSON.stringify({ amount: 80000, date: '2026-09-10', category: 'food' }),
    actual_json: JSON.stringify({ amount: 80000, date: null, category: 'transport' }),
    field_results: [
      { field: 'intent', compared: true, matched: true },
      { field: 'amount', compared: true, matched: true },
      { field: 'date', compared: true, matched: false },
      { field: 'activity', compared: true, matched: true },
      { field: 'category', compared: true, matched: false },
      { field: 'subcategory', compared: false, matched: false },
      { field: 'money_source', compared: false, matched: false },
      { field: 'currency', compared: true, matched: true }
    ],
    json_valid: true,
    latency_ms: 1240,
    input_tokens: 220,
    output_tokens: 45,
    cost: 0.00012,
    error: null,
    attempts: 1
  };

  const ERROR_CASE = {
    id: 202,
    row_number: 44,
    status: 'error',
    message: 'compré unos zapatos',
    expected_json: JSON.stringify({ amount: 120000 }),
    actual_json: null,
    field_results: [],
    json_valid: false,
    latency_ms: 832,
    input_tokens: 0,
    output_tokens: 0,
    cost: 0,
    error: 'The AI provider failed during evaluation.',
    attempts: 1
  };

  const ALL_CASES = [FAILED_CASE, ERROR_CASE];

  const OTHER_MODEL_RUN = run({
    id: 43,
    model: 'mistral-small-latest',
    provider: 'mistral',
    status: 'completed',
    progress: 1,
    started_at: '2026-09-13T09:00:00Z',
    completed_at: '2026-09-13T09:05:00Z',
    metrics: {
      total_cases: 1000,
      passed_cases: 958,
      full_record_accuracy: 0.958,
      accuracy: 0.958,
      json_validity: 1.0,
      average_latency: 1.4,
      total_cost: 0.42,
      cost: 0.42
    }
  });

  function filterCases(status, q) {
    let list = ALL_CASES;
    if (status && status !== 'all') list = list.filter((c) => c.status === status);
    if (q) list = list.filter((c) => c.message.toLowerCase().includes(q.toLowerCase()));
    return list;
  }

  // Mocks the whole /expense-evaluations* namespace. store.shape:
  //   { running, completed, history, latestPost, startErrors, completeAfterPolls }
  function mockEvaluationApi(page, store) {
    page.route(/\/expense-evaluations(\S*)?/, (route) => {
      handleEvaluationRoute(route, store);
    });
  }

  function handleEvaluationRoute(route, store) {
    const req = route.request();
    const url = new URL(req.url());
    const path = url.pathname.endsWith('/') ? url.pathname.slice(0, -1) : url.pathname;

    if (req.method() === 'POST' && path === '/expense-evaluations/start') {
      store.latestPost = req.postDataJSON();
      if (store.startErrors) {
        route.fulfill({ status: 422, contentType: 'application/json', body: JSON.stringify({ ok: false, errors: store.startErrors }) });
        return;
      }
      store.history = [RUNNING].concat(store.history || []);
      route.fulfill({ status: 201, contentType: 'application/json', body: JSON.stringify({ ok: true, replayed: false, run: RUNNING }) });
      return;
    }

    if (req.method() === 'GET' && path === '/expense-evaluations') {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ runs: store.history || [] }) });
      return;
    }

    const casesMatch = path.match(/^\/expense-evaluations\/\d+\/cases$/);
    if (req.method() === 'GET' && casesMatch) {
      const cases = filterCases(url.searchParams.get('status'), url.searchParams.get('q'));
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({
        cases,
        total: cases.length,
        counts: { passed: 0, failed: 0, error: 0, pending: 0 }
      }) });
      return;
    }

    const retryMatch = path.match(/^\/expense-evaluations\/\d+\/retry$/);
    if (req.method() === 'POST' && retryMatch) {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, rerun_count: store.retryCount || 2 }) });
      return;
    }

    const detailMatch = path.match(/^\/expense-evaluations\/\d+$/);
    if (req.method() === 'GET' && detailMatch) {
      store.polls = (store.polls || 0) + 1;
      const payload = store.polls >= store.completeAfterPolls ? store.completed : store.running;
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ run: payload }) });
      return;
    }

    route.continue();
  }

  const CSV = [
    'message,expected_json',
    '"me gasté 20mil hoy en almuerzo","{""amount"":20000}"',
    '"ayer pagué 35 lucas de uber con la visa","{""amount"":35000}"'
  ].join('\n');

  async function uploadDataset(page) {
    await page.setInputFiles('input[data-testid="evaluation-dataset-file"]', {
      name: DATASET,
      mimeType: 'text/csv',
      buffer: Buffer.from(CSV, 'utf-8')
    });
  }

  async function openEvaluationTab(page) {
    await page.goto('/expense-evaluations');
    await expect(page.getByTestId('playground-evaluation-panel')).toBeVisible();
  }

  test('the Evaluation tab exposes the dataset/provider/model form', async ({ page }) => {
    await signUp(page);
    await openEvaluationTab(page);

    await expect(page.getByRole('heading', { name: 'AI Evaluation' })).toBeVisible();
    await expect(page.getByTestId('evaluation-dataset-file')).toBeVisible();
    await expect(page.getByTestId('evaluation-provider')).toHaveValue('openrouter');
    await expect(page.getByTestId('evaluation-provider')).toContainText('OpenRouter');
    await expect(page.getByTestId('evaluation-model')).toHaveValue('mistral/mistral-small-latest');
    await expect(page.getByTestId('evaluation-filename')).toHaveValue('gastos.csv');
    await expect(page.getByTestId('evaluation-start')).toBeVisible();
  });

  test('starting an evaluation polls the run and renders the completed metrics', async ({ page }) => {
    await signUp(page);
    mockEvaluationApi(page, { running: RUNNING, completed: COMPLETED, completeAfterPolls: 2 });
    await openEvaluationTab(page);

    await uploadDataset(page);
    await page.getByTestId('evaluation-start').click();

    // Running state: progress bar at 50% + status badge, polled from the API.
    await expect.poll(() => page.locator('#pgEvalRunProgress').evaluate((el) => el.style.width)).toBe('50%');
    await expect(page.getByTestId('evaluation-history-row').first()).toBeVisible();

    // Completed state: aggregated metrics, field accuracy and Full Record line.
    await expect(page.locator('#pgEvalRunStatus')).toContainText('Completada', { timeout: 15000 });
    await expect(page.locator('#pgEvalTotal')).toHaveText('1000');
    await expect(page.locator('#pgEvalPassed')).toHaveText('942');
    await expect(page.locator('#pgEvalFailed')).toHaveText('58');
    await expect(page.locator('#pgEvalJsonValid')).toHaveText('99%');
    await expect(page.locator('#pgEvalCost')).toHaveText('$0.18');
    await expect(page.locator('#pgEvalLatency')).toHaveText('1.20s');
    await expect(page.locator('#pgEvalFieldAccuracy')).toContainText('Full Record');
    await expect(page.locator('#pgEvalFieldAccuracy').locator('div', { hasText: 'amount' }).first()).toContainText('100%');
    await expect(page.locator('#pgEvalFieldAccuracy').locator('div', { hasText: 'date' }).first()).toContainText('96%');
  });

  test('dataset validation errors from the backend are surfaced', async ({ page }) => {
    await signUp(page);
    const store = {
      running: RUNNING,
      completed: COMPLETED,
      completeAfterPolls: 2,
      startErrors: [
        'Missing required column(s): expected_json. Expected: message, expected_json.',
        'Row 3: message must not be empty or expected_json is not valid JSON.'
      ]
    };
    mockEvaluationApi(page, store);
    await openEvaluationTab(page);

    await uploadDataset(page);
    await page.getByTestId('evaluation-start').click();

    await expect(page.locator('#pgEvalError')).toBeVisible();
    await expect(page.locator('#pgEvalError')).toContainText('Missing required column(s): expected_json');
    await expect(page.locator('#pgEvalError')).toContainText('Row 3: message must not be empty');

    // The request body carried the full dataset, filename, provider and model.
    expect(store.latestPost.filename).toBe(DATASET);
    expect(store.latestPost.provider).toBe('openrouter');
    expect(store.latestPost.model).toBe(MODEL);
    expect(store.latestPost.dataset).toContain('ayer pagué 35 lucas de uber');

    // The run never started, so no results panel is rendered.
    await expect(page.locator('#pgEvalResults')).toBeHidden();
  });

  test('the form requires a model before submitting', async ({ page }) => {
    await signUp(page);
    const store = { running: RUNNING, completed: COMPLETED, completeAfterPolls: 2 };
    mockEvaluationApi(page, store);
    await openEvaluationTab(page);

    await uploadDataset(page);
    await page.getByTestId('evaluation-model').fill('');
    await page.getByTestId('evaluation-start').click();

    await expect(page.locator('#pgEvalError')).toBeVisible();
    await expect(page.locator('#pgEvalError')).toContainText('Indica un modelo.');

    const postsSeen = [];
    page.on('request', (r) => {
      if (r.method() === 'POST' && r.url().includes('/expense-evaluations/start')) postsSeen.push(r.url());
    });
    await page.getByTestId('evaluation-start').click();
    expect(postsSeen.length).toBe(0);
  });

  test('failed cases can be searched by message and filtered by status', async ({ page }) => {
    await signUp(page);
    mockEvaluationApi(page, { running: RUNNING, completed: COMPLETED, completeAfterPolls: 1 });
    await openEvaluationTab(page);

    await uploadDataset(page);
    await page.getByTestId('evaluation-start').click();

    // Default status=failed: one failed case with a badge per mismatched field.
    await expect(page.getByTestId('evaluation-failed-case').first()).toBeVisible({ timeout: 15000 });
    const failedRow = page.getByTestId('evaluation-failed-case').filter({ hasText: 'ayer gasté 80 lucas' });
    await expect(failedRow).toContainText('23');
    await expect(failedRow).toContainText('"amount":80000');
    await expect(failedRow).toContainText('date');
    await expect(failedRow).toContainText('category');
    await expect(failedRow.locator('span.badge.bg-danger')).toHaveCount(2);

    // Search by message narrows the failing rows.
    await page.getByTestId('evaluation-failed-query').fill('80 lucas');
    await page.getByRole('button', { name: 'Filtrar' }).click();
    await expect(page.getByTestId('evaluation-failed-case')).toHaveCount(1);

    // Filter by status shows the provider error case once the search clears.
    await page.getByTestId('evaluation-failed-query').fill('');
    await page.getByTestId('evaluation-failed-status').selectOption('error');
    const errorRow = page.getByTestId('evaluation-failed-case').filter({ hasText: 'compré unos zapatos' });
    await expect(errorRow).toBeVisible();
    await expect(errorRow).toContainText('The AI provider failed during evaluation');
  });

  test('the model comparison table lists completed runs for the same dataset', async ({ page }) => {
    await signUp(page);
    mockEvaluationApi(page, {
      running: RUNNING,
      completed: COMPLETED,
      completeAfterPolls: 1,
      history: [COMPLETED, OTHER_MODEL_RUN]
    });
    await openEvaluationTab(page);

    await uploadDataset(page);
    await page.getByTestId('evaluation-start').click();

    await expect(page.locator('#pgEvalCompareBody tr')).toHaveCount(2, { timeout: 15000 });
    const compareRows = page.locator('#pgEvalCompareBody tr');
    await expect(compareRows.first()).toContainText(MODEL);
    await expect(compareRows.first()).toContainText('94%');
    await expect(compareRows.nth(1)).toContainText('mistral-small-latest');
    await expect(compareRows.nth(1)).toContainText('96%');

    // The failed-cases view is still reachable from the completed run.
    await expect(page.getByTestId('evaluation-failed-case').first()).toBeVisible();
  });
});