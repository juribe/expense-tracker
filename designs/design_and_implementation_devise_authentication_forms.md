**Devise Authentication UI Spec (split auth layout)**

| Screen | Layout | Core components | Interaction & states |
|--------|--------|-----------------|----------------------|
| **All signed-out Devise screens** | `layouts/auth.html.erb`: full-height gradient surface, two-column shell (`auth-intro` + `auth-card`). The intro carries the brand, headline, three product benefits and a decorative dashboard preview. | `auth-page`, `auth-shell`, `auth-intro`, `auth-features`, `auth-preview`, `auth-card`; form markup uses `auth-heading`, `auth-field`, `auth-input`, `auth-toggle`, `auth-submit`, `auth-footer-link`. | Light and dark themes (stored `etTheme`), mobile stacks intro above the card and hides the preview, top-right session link hidden below 780px. |
| **Sign In** | Intro + card. | Email, password with visibility toggle, remember me, inline “¿Olvidaste tu contraseña?”, primary submit with arrow. | Devise error messages render inside the card; submit disables and shows a spinner while in flight. |
| **Sign Up** | Same shell. | Name, email, password and confirmation with visibility toggles; minimum-length hint; privacy note; link to sign in. | Server-side Devise validation renders errors inside the card; no client-side validation duplication. |
| **Forgot Password** | Same shell. | Email field + submit; link back to sign in. | Successful POST renders an inline success card with a mail icon and a link back to sign in. |
| **Reset Password** | Same shell. | Hidden reset token, new password and confirmation with visibility toggles. | Success renders an inline confirmation with `data-auto-redirect-to` (3s redirect to the dashboard). Errors keep the form in place. |
| **Confirmation / Unlock** | Same shell. | Email field + submit, shared Devise links. | Uses the same card language for consistency if confirmable/lockable are enabled. |
| **Profile edit** | Application shell. | Unchanged Bootstrap profile form. | Deliberately excluded: `layout_for_request` keeps `registrations#edit/update/destroy` in the application layout. |

**Implementation notes**

- Layout selection lives in `ApplicationController#layout_for_request`. Devise controllers use `auth`; profile management uses `application`. Session state is not used because the reset-password success action signs the user in before rendering.
- Styles live in `app/assets/stylesheets/auth.css`, loaded only by the auth layout. Classes are scoped under `.auth-page`.
- Icons use the vendored Tabler font (`ti ti-*`); no inline SVG, inline styles or inline scripts (CSP keeps a strict `style-src`).
- Copy lives in `config/locales/es.yml` under `auth` (including `auth.intro`). The `auth.intro.title_html` key is HTML-safe.
- Password visibility, submit spinner and the reset auto-redirect reuse `app/assets/javascripts/auth_form.js`.
- Reference mockup: `mockups/signup_control_de_gastos_gradient.html` (provided design).
