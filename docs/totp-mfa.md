# TOTP MFA en Yogasto

Yogasto admite TOTP como segundo factor independiente, además de Passkeys y
llaves WebAuthn. Los usuarios pueden tener cualquier combinación de métodos.

## Gemas

- `rotp` 6.4.0: generación y verificación de códigos TOTP.
- `rqrcode` 3.2.0: generación del QR de configuración.

No se añadió una gema completa de MFA.

## Migración

`db/migrate/*_create_totp_credentials.rb` crea `totp_credentials`:

- `user_id` único, UUID y llave foránea.
- `secret` cifrado con Active Record Encryption.
- `last_used_timestamp` para impedir la reutilización de un código.

El secreto solo existe en la base de datos cuando el usuario confirma un código
válido. El secreto pendiente de configuración se guarda temporalmente en la
sesión cifrada y vence a los 10 minutos.

## Flujo de configuración

1. `Perfil > Seguridad de la cuenta` exige la contraseña antes de mostrar la información.
2. El usuario selecciona **Configurar aplicación de autenticación**.
3. Yogasto genera un secreto base32 de 160 bits y muestra:
   - código QR compatible con Google Authenticator, Microsoft Authenticator y apps TOTP estándar;
   - la clave manual en grupos de cuatro caracteres, con botón para copiar.
4. El usuario escanea el QR e ingresa el código de seis dígitos.
5. Solo si el código es válido se crea/actualiza `totp_credentials`.
6. Si el usuario no tenía códigos de recuperación, se generan y muestran una sola vez.
7. El QR y el secreto pendiente se eliminan de la sesión después de confirmar.

**Cambiar configuración** inicia un nuevo secreto pendiente. La configuración
anterior sigue activa hasta que el nuevo código sea confirmado.

## Flujo de login

- Sin MFA: contraseña y sesión normal.
- Con TOTP: contraseña y luego código TOTP; no se crea una sesión completa antes de validarlo.
- Con llave WebAuthn: contraseña y luego llave.
- Con TOTP y llave WebAuthn: la pantalla 2FA muestra ambos formularios.
- Con Passkey: la passkey sigue siendo un login completo y no pide TOTP.
- Con códigos de recuperación: se pueden usar en la pantalla 2FA.

## Seguridad

- Secreto cifrado en reposo con Active Record Encryption.
- Secreto pendiente solo en sesión cifrada, con vencimiento de 10 minutos.
- Tolerancia TOTP de ±30 segundos.
- `last_used_timestamp` impide reutilizar el mismo paso temporal.
- Rate limiting en login TOTP y en confirmación de configuración.
- Parámetros `totp_code`, `otp_code` y `totp_secret` excluidos de logs.
- Página de seguridad y configuración con `Cache-Control: no-store`.
- Reautenticación con contraseña de 10 minutos para iniciar, confirmar, cancelar o desactivar TOTP.
- Códigos de recuperación bcrypt, de un solo uso, regenerables e invalidantes.
- Desactivar TOTP no elimina códigos de recuperación si queda una llave WebAuthn; desactivar WebAuthn tampoco los elimina si queda TOTP.

## Variables de entorno

TOTP no requiere variables nuevas. Sí requiere las claves de Active Record
Encryption que el proyecto ya usa en producción:

```bash
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=...
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=...
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=...
```

Sin estas claves, producción no arranca. Mantener el servidor sincronizado por
NTP para que los códigos TOTP coincidan con el teléfono.

## Desarrollo

```bash
bundle install
bin/rails db:migrate
bin/rails test test/models/totp_credential_test.rb \
  test/models/user_mfa_test.rb \
  test/controllers/security_settings_controller_test.rb \
  test/controllers/users/totp_authentications_controller_test.rb \
  test/controllers/users/two_factor_authentications_controller_test.rb \
  test/controllers/users/recovery_code_authentications_controller_test.rb \
  test/controllers/sessions_controller_test.rb
```

Prueba manual:

1. Inicia sesión y abre `Perfil > Seguridad de la cuenta`.
2. Confirma la contraseña.
3. Configura la aplicación de autenticación y escanea el QR.
4. Ingresa el código de seis dígitos y confirma.
5. Guarda los códigos de recuperación mostrados.
6. Cierra sesión e inicia con contraseña; la app debe pedir TOTP.
7. Verifica que una passkey siga iniciando sesión sin pedir TOTP.
8. Prueba un código de recuperación.
9. Desactiva TOTP y confirma que el login vuelve a su comportamiento anterior.

## Limitaciones

- El login con Passkey es un login completo; TOTP aplica después de la contraseña.
- Si el usuario pierde el teléfono, la llave WebAuthn y todos los códigos de recuperación, se requiere soporte manual.
- No se implementó TOTP por SMS ni correo.
- Cambiar de teléfono requiere iniciar la configuración de TOTP de nuevo con reautenticación.
- La recuperación de contraseña por correo no omite TOTP; los códigos de recuperación son el mecanismo de auto-recuperación.
