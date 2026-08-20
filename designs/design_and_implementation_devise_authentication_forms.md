**Devise Authentication UI Spec (Bootstrap 5)**  

| Screen | Layout & Grid | Core Components (Bootstrap classes) | Colors & Typography | Interaction & States |
|--------|---------------|--------------------------------------|----------------------|----------------------|
| **Sign In** | Centered card `col-md-6 col-lg-4 mx-auto my-5` | `<form>` `<div class="mb-3">` `<input type="email" class="form-control form-control-lg">` `<input type="password" class="form-control form-control-lg">` `<div class="form-check"><input class="form-check-input" type="checkbox"> <label class="form-check-label">Remember me</label></div>` `<a href="#" class="link-primary">Forgot password?</a>` `<button class="btn btn-primary w-100 btn-lg">Sign In</button>` `<p class="mt-3 text-center">Don’t have an account? <a href="#" class="link-secondary">Sign Up</a></p>` | Background `#f8f9fa`; Card `bg-white shadow-sm`; Primary `#0d6efd`; Text `#212529`; Font‑weight 500, size 1rem (lg 1.125rem for inputs). | **Default:** normal. **Focus:** `:focus` adds `border-primary` & `shadow-sm`. **Error:** `is-invalid` → red border `#dc3545` + `.invalid-feedback`. **Disabled:** `disabled` → `opacity-50`. **Loading:** button `disabled` + spinner `<span class="spinner-border spinner-border-sm me-2"></span>`. |
| **Sign Up** | Same card size as Sign In | Fields: Name, Email, Password, Password Confirmation – each `<input class="form-control">`. Password fields include toggle visibility icon (`<i class="bi bi-eye-slash toggle-pw"></i>` positioned absolute). `<button class="btn btn-success w-100">Create Account</button>` plus link back to Sign In. | Success button `#198754`. Error messages same as Sign In. | Validation: live check on blur → `is-invalid`/`is-valid`. Password match shows green check (`is-valid`). Loading spinner on button. |
| **Forgot Password** | Card `col-md-5 col-lg-4 mx-auto my-5` | Single email `<input class="form-control">` + submit `<button class="btn btn-primary w-100">Send Reset Link</button>` + link back to Sign In. | Same palette as Sign In. | After successful POST → replace form with `<div class="alert alert-success">We’ve emailed a reset link.</div>`; button shows spinner while submitting. |
| **Reset Password** | Card identical to Sign Up | New Password & Confirmation fields (same toggle icon). `<button class="btn btn-primary w-100">Reset Password</button>` + link to Sign In. | Same as Sign Up. | Errors: weak password (`invalid-feedback`), mismatch (`is-invalid`). On success → `<div class="alert alert-success">Your password has been updated.</div>` and auto‑redirect after 3 s. |

**Common Utilities**  
- Container: `<div class="container-fluid d-flex align-items-center justify-content-center min-vh-100">`.  
- Spacing: `mb-3` for fields, `mt-4` for buttons.  
- Responsive breakpoints: stack fields full‑width on `<576px`; keep card centered.  
- Accessibility: `<label for="...">` linked to inputs; `aria-describedby` for error messages; focus order logical; color contrast ≥ 4.5:1.  

**Responsive Behavior**  
- Mobile (`<576px`): card width `90%`, inputs full‑width, text centered.  
- Tablet (`≥768px`): card width `70%`.  
- Desktop (`≥992px`): card width `40%`.  

**Interaction Summary**  
- Hover on buttons: `btn-primary:hover` → darken 5 %.  
- Links: underline on hover.  
- Form submit: prevent double‑click via `disabled` + spinner.  
- All forms retain Devise `flash` messages styled with `.alert` components.  