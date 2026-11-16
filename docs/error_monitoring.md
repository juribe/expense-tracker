# Error monitoring with Rollbar

Yogasto reports unexpected production errors to [Rollbar](https://rollbar.com).
The integration is server-side only: no JavaScript SDK is loaded in the browser.

## How it works

- `rollbar` is configured in `config/initializers/rollbar.rb`.
- Rollbar subscribes to the Rails error reporter (`Rails.error`). That covers
  unhandled controller requests and Solid Queue job failures without adding
  `rescue_from` handlers to every controller or job.
- Expected exceptions (for example `ActiveRecord::RecordNotFound`,
  `ActionController::RoutingError` and invalid CSRF tokens) are ignored.
- A payload transform (`ErrorReporting::RollbarPayloadSanitizer`) removes
  request bodies, parameters, cookies, sessions, headers, job arguments,
  mailer parameters, stack-frame locals and sensitive nested values before the
  event is sent.
- The application version is the Git commit SHA, passed to Rails as
  `APP_VERSION`.
- The Kamal deploy workflow records successful deployments in Rollbar using the
  same SHA.

## Required environment variables

| Variable | Required | Where it lives | Purpose |
| --- | --- | --- | --- |
| `ROLLBAR_ACCESS_TOKEN` | Production | GitHub repository secret and `.env` locally | Rollbar `post_server_item` token used by Rails |
| `APP_VERSION` | Production | Set by the deploy workflow and `config/deploy.yml` | Git commit SHA used as Rollbar `code_version` and deploy revision |
| `ROLLBAR_ENV` | Optional | Kamal/container environment | Overrides the Rollbar environment name (defaults to `Rails.env`) |
| `ROLLBAR_ENABLED` | Optional | Kamal/container environment | Set to `false` to disable reporting temporarily |
| `ROLLBAR_SERVER_ACCESS_TOKEN` | Optional | GitHub repository secret | Dedicated token for Rollbar deployment notifications |

Reporting is disabled by default in `development` and `test`, and when
`ROLLBAR_ACCESS_TOKEN` is missing. A missing token never prevents the
application from booting. A future `RAILS_ENV=staging` environment is enabled
automatically when the token is present.

`ROLLBAR_SERVER_ACCESS_TOKEN` is not passed into the container. It is only read
by the GitHub Actions deployment-notification step, which falls back to
`ROLLBAR_ACCESS_TOKEN` when the dedicated token is not configured.

## Create the Rollbar project and token

1. Create a project in Rollbar and choose **Ruby** as the platform.
2. Open the project's **Settings → Project Access Tokens**.
3. Copy the `post_server_item` token.
4. Store it as the `ROLLBAR_ACCESS_TOKEN` repository secret:

   ```sh
   gh secret set ROLLBAR_ACCESS_TOKEN
   ```

   For local development, add the same variable to `.env`. The local value is
   ignored by design because reporting is disabled outside production/staging.

5. Optional: create a separate token for deployment notifications and store it
   as `ROLLBAR_SERVER_ACCESS_TOKEN`. The deploy workflow prefers it and falls
   back to `ROLLBAR_ACCESS_TOKEN` when it is absent.

## Kamal configuration

`config/deploy.yml` declares:

```yaml
env:
  clear:
    APP_VERSION: <%= ENV["APP_VERSION"]... %>
  secret:
    - ROLLBAR_ACCESS_TOKEN
```

The deploy workflow writes `.kamal/secrets` from the environment before running
Kamal. For a manual deployment, copy `.kamal/secrets.example` to
`.kamal/secrets` and export `ROLLBAR_ACCESS_TOKEN` first:

```sh
export ROLLBAR_ACCESS_TOKEN="..."
export APP_VERSION="$(git rev-parse HEAD)"
cp .kamal/secrets.example .kamal/secrets
bundle exec kamal setup
```

Do not commit `.kamal/secrets`, `.env`, tokens or credentials.

## Deployment tracking

The GitHub Actions deploy workflow:

1. Checks out the same commit whose Tests run succeeded.
2. Sets `APP_VERSION` to `github.event.workflow_run.head_sha` (or
   `github.sha` for a manual deploy).
3. Runs `kamal setup`.
4. Only after a successful step 3, posts the deployment to
   `https://api.rollbar.com/api/1/deploy/` with `status: "succeeded"`.

A failed or cancelled deployment never reaches the notification step. If the
notification itself fails, the workflow emits a warning but does not mark the
deployment as failed.

Manual deploys also receive `APP_VERSION` in the container from
`config/deploy.yml`, falling back to `git rev-parse HEAD`. Manual deployments do
not automatically create a Rollbar deploy record; post one with:

```sh
curl --fail --silent --show-error \
  -X POST "https://api.rollbar.com/api/1/deploy/" \
  -H "Content-Type: application/json" \
  -d "{\"access_token\":\"$ROLLBAR_ACCESS_TOKEN\",\"environment\":\"production\",\"revision\":\"$(git rev-parse HEAD)\",\"local_username\":\"manual\",\"status\":\"succeeded\"}"
```

## What is reported

- Unhandled Rails exceptions.
- Unhandled background job failures, including email, WhatsApp, imports,
  transaction recognition and scheduled tasks.
- Explicit `Rails.error.report` failures from libraries and scheduled jobs.
- Handled reports keep their warning/info severity.

Not reported as application exceptions:

- Normal validation failures.
- Expected authentication and authorization failures.
- Expected user input errors and business-rule rejections.
- Expected 404s and routing errors.
- Handled external-service responses.

## Privacy and sensitive data

Rollbar must never become a second store for financial or personal data. The
integration applies several layers:

1. Rails parameter filtering in
   `config/initializers/filter_parameter_logging.rb` covers financial,
   identity, bank, card, upload, email, WhatsApp and API-payload fields.
2. Rollbar `scrub_fields` merges the Rails filter list with domain-specific
   fields (card numbers, account numbers, balances, descriptions, tokens, TOTP,
   Epayco credentials and so on).
3. `scrub_headers` covers `Authorization`, `Cookie`, `Set-Cookie`,
   `X-Api-Key`, CSRF and forwarded IP headers.
4. `collect_user_ip` is false and extra frame data is `:none`, so IP addresses
   and local variables are not collected.
5. The payload transform removes the request body, params, `GET`, `POST`,
   cookies, session, headers and client IP. URLs keep only their path; query
   strings are dropped.
6. Job `arguments`, ActionMailer `params`, stack-frame locals and nested
   sensitive keys are removed. Job class, job id, controller and action remain
   available for diagnosis.
7. Exception messages and other diagnostic strings are redacted for emails,
   card/account/phone numbers, bearer tokens, JWTs and `password=...` style
   values, then truncated to 500 characters.
8. Person context contains only the internal user id. Email, username and IP
   are never sent.
9. The payload is not logged locally (`log_payload` is false), and no frontend
   monitoring SDK is installed.

Pattern-based message redaction cannot recognize every possible free-form
personal detail. This is why request bodies, job arguments and financial fields
are removed entirely instead of relying on scrubbing alone. Do not add custom
Rollbar context containing user-entered content.

## Testing the integration

Automated tests never send events to Rollbar. They stub the notifier and verify
configuration, sanitization and reporting behavior:

```sh
bin/rails test test/services/error_reporting/rollbar_settings_test.rb
bin/rails test test/services/error_reporting/rollbar_payload_sanitizer_test.rb
bin/rails test test/lib/rollbar_error_reporting_test.rb
bin/rails test test/config/deployment_tracking_test.rb
```

## Verify errors appear in Rollbar

Use a controlled message rather than a real production exception. For example,
from the production container:

```sh
bundle exec kamal app exec --reuse \
  'bin/rails runner "Rollbar.info(\"Rollbar verification from production\")"'
```

Or locally, explicitly enabling the client for one message:

```sh
ROLLBAR_ACCESS_TOKEN="$ROLLBAR_ACCESS_TOKEN" bin/rails runner '
  Rollbar.with_config(enabled: true, environment: "development", use_async: false) do
    Rollbar.info("Rollbar verification from local")
  end
'
```

Then open the Rollbar project and check **Items** and **Deploys**. The item
should show the `code_version` (Git SHA) and no request body, job arguments,
email addresses or financial values.

## Disable Rollbar temporarily

Set `ROLLBAR_ENABLED=false` in the production environment and redeploy (or
remove `ROLLBAR_ACCESS_TOKEN`). Reporting is disabled at boot, while the
application continues to operate normally. Disabling monitoring does not change
application behavior.

## Limitations

- Rollbar dashboard access, notification rules and team permissions are managed
  in Rollbar, not in this repository.
- The deployment notification is best-effort. A Rollbar outage does not fail a
  deployment and leaves that deployment untracked.
- Message redaction is pattern-based; avoid putting free-form user content into
  exception messages or custom Rollbar context.
- Only server-side monitoring is configured. Browser-side monitoring is out of
  scope.
