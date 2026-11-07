# Passkeys y verificación en dos pasos WebAuthn

Yogasto usa [`devise-webauthn`](https://github.com/cedarcode/devise-webauthn) `0.5.1`
sobre Devise, con `webauthn` `3.5.0`. El inicio de sesión con correo y contraseña
se conserva; las passkeys y el segundo factor son opcionales.

## Qué se implementó

- Registro y eliminación de **passkeys** (primer factor) desde `Perfil > Seguridad de la cuenta`.
- Inicio de sesión con passkey desde la pantalla de acceso, sin reemplazar el formulario de contraseña.
- **Segundo factor WebAuthn opcional** mediante llaves de seguridad. Registrar una passkey no activa 2FA.
- **Segundo factor TOTP opcional** con aplicaciones de autenticación; se documenta en `docs/totp-mfa.md`.
- Desactivar las llaves de segundo factor elimina esos credenciales y los códigos de recuperación solo si no queda ningún otro método MFA; conserva las passkeys.
- **Códigos de recuperación** de un solo uso, guardados únicamente como hashes bcrypt, regenerables y descargables/copiables una sola vez.
- La página `Perfil > Seguridad de la cuenta` permanece bloqueada hasta confirmar la contraseña; después de confirmarla, la información y las acciones quedan disponibles durante 10 minutos.
- Reautenticación con contraseña durante 10 minutos para acciones sensibles.
- Desafíos WebAuthn con caducidad de 5 minutos y protección contra reutilización.
- Validación de propiedad: cada usuario solo puede listar o eliminar sus propias credenciales.

## Modelo de datos

Migraciones:

- `db/migrate/*_create_webauthn_credentials.rb`
- `db/migrate/*_add_webauthn_id_to_users.rb`
- `db/migrate/*_create_recovery_codes.rb`

Tablas:

- `users.webauthn_id`: identificador estable del usuario para WebAuthn.
- `webauthn_credentials`: credenciales WebAuthn con `authentication_factor` (`first_factor` para passkeys, `second_factor` para llaves de seguridad).
- `recovery_codes`: `code_digest` bcrypt, `used_at`; nunca se guarda el código en claro.

## Configuración WebAuthn

`config/initializers/webauthn.rb` configura:

- `rp_name = "Yogasto"`.
- `rp_id` explícito a partir del origen o de `WEBAUTHN_RP_ID`.
- `allowed_origins` explícito, sin comodines.
- Rechazo de orígenes HTTP en producción.
- Timeout de opciones de 120 segundos.

Variables de entorno:

```bash
# Producción
WEBAUTHN_ORIGIN=https://yogasto.co
WEBAUTHN_RP_ID=yogasto.co

# Staging (usar un RP ID propio para no compartir credenciales con producción)
WEBAUTHN_ORIGIN=https://staging.yogasto.co
WEBAUTHN_RP_ID=staging.yogasto.co

# Desarrollo local (valores por defecto)
WEBAUTHN_ORIGIN=http://localhost:3000
WEBAUTHN_RP_ID=localhost
```

Reglas importantes:

1. El origen debe coincidir exactamente con el origen que ve el navegador, incluido el puerto.
2. El dominio debe servirse por HTTPS en producción y staging. `localhost` es la excepción de desarrollo.
3. No se admiten comodines, rutas ni orígenes HTTP en producción.
4. Cambiar de dominio o de `rp_id` invalida las credenciales existentes para ese dominio; los usuarios deben registrar nuevas passkeys.
5. Si se sirve el mismo dominio con y sin `www`, hay que decidir un único origen canónico o añadir ambos orígenes explícitos y un `rp_id` común.

## Puesta en marcha

```bash
bundle install
bin/rails db:migrate
```

En cada entorno:

1. Configurar `WEBAUTHN_ORIGIN` y `WEBAUTHN_RP_ID`.
2. Asegurar HTTPS y que el dominio resuelva al entorno correcto.
3. Reiniciar la aplicación después de cambiar las variables.
4. Verificar que `bin/rails routes | grep -E "passkey|two_factor|recovery"` muestra las rutas.
5. Probar en un navegador real: abrir `Perfil > Seguridad de la cuenta` y comprobar que primero pide la contraseña; después registrar passkey, cerrar sesión, iniciar con passkey, activar 2FA, cerrar sesión, iniciar con contraseña + llave y usar un código de recuperación.

## Pruebas

Los tests usan `WebAuthn::FakeClient`; no requieren biometría ni navegador real:

```bash
bin/rails test test/models/user_webauthn_test.rb \
  test/models/webauthn_credential_test.rb \
  test/models/recovery_code_test.rb \
  test/controllers/security_settings_controller_test.rb \
  test/controllers/users/passkeys_controller_test.rb \
  test/controllers/users/two_factor_authentications_controller_test.rb \
  test/controllers/users/recovery_code_authentications_controller_test.rb \
  test/controllers/users/second_factor_webauthn_credentials_controller_test.rb \
  test/controllers/sessions_controller_test.rb

bin/rails test
```

## Limitaciones y decisiones

- No se implementó TOTP por SMS ni por correo; el TOTP por aplicación se documenta en `docs/totp-mfa.md`.
- El inicio con passkey es un inicio completo: la passkey ya combina posesión del dispositivo y verificación del usuario. TOTP aplica al flujo de contraseña, no después de una passkey.
- No existe recuperación automática si el usuario pierde todas sus passkeys, su llave de segundo factor, su aplicación TOTP y sus códigos de recuperación. En ese caso se requiere soporte manual.
- La recuperación con códigos exige primero la contraseña y luego un código; no sustituye la contraseña.
- Los códigos de recuperación se muestran una sola vez. Si se regeneran, los anteriores dejan de funcionar inmediatamente.
- Los métodos de segundo factor son WebAuthn y TOTP; no se incluyó SMS.
- La verificación en navegadores reales depende de que el dominio, el RP ID y el origen coincidan y de que el navegador soporte WebAuthn.
