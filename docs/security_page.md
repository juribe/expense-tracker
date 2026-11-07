# Seguridad

La página pública vive en `/seguridad` y se administra desde Maglev. La ruta
anterior `/security` responde con un 301 a la nueva URL.

## Administración

En Maglev, abrir la página **Seguridad** (`seguridad`). La página reutiliza el
navbar, el footer, el hero institucional y las secciones de seguridad del tema.

Secciones editables:

- **Hero institucional**: etiqueta, título, descripción, texto complementario e
  ilustración de escudo.
- **Protección de la cuenta**: contraseña, passkeys y TOTP. Cada tarjeta es
  editable y puede ocultarse.
- **Protección de la información**: medidas técnicas y operativas verificadas.
- **Procesamiento de información**: categorías de datos y funciones.
- **Control de la información**: acciones del usuario y consideraciones sobre
  cierre de cuenta y backups.
- **Infraestructura y proveedores**: preguntas sobre OVHcloud, proveedores
  externos, correos, backups y tarjetas.
- **Reportar un problema de seguridad**: CTA con correo de contacto.
- **SEO de la página**: title, meta description, Open Graph y canonical.

El contenido se guarda en Maglev después de la primera carga. La semilla del
tema es solo el punto de partida.

## Afirmaciones verificadas

- La aplicación se aloja en infraestructura de OVHcloud ubicada en Canadá
  (confirmado por el responsable del producto).
- La producción fuerza HTTPS (`config/environments/production.rb`).
- Las contraseñas se gestionan con Devise y bcrypt; no se almacenan en texto
  plano.
- Passkeys y TOTP están implementados como métodos opcionales. Passkeys usan
  WebAuthn y TOTP usa aplicaciones compatibles.
- Los secretos TOTP se cifran con Active Record Encryption. Los códigos de
  recuperación se guardan como hashes bcrypt.
- La página de seguridad de la cuenta exige reautenticación con contraseña y no
  se cachea.
- Existe una política de seguridad de contenido (CSP), cookies seguras en
  producción y límites de uso en accesos sensibles y formularios públicos.
- Los tokens de Gmail, la telemetría de IA y las credenciales de proveedores se
  protegen con cifrado en reposo.
- La información de cada cuenta se gestiona con controles de autorización.
- El contenido de los correos procesados se elimina de los sistemas de
  procesamiento al terminar; si el procesamiento falla, puede conservarse
  mientras se reintenta.
- Yogasto no almacena números completos de tarjetas; el pago lo procesa ePayco.
- Los proveedores externos publicados coinciden con la Política de privacidad:
  OVHcloud, ePayco, Mistral, OpenRouter, Google/Gmail, Meta/WhatsApp y
  Cloudflare.
- La página no afirma certificaciones, auditorías independientes ni garantías
  de riesgo cero.

## Pendiente de confirmación

Los detalles técnicos y legales que no están confirmados se documentan en
[docs/security_page_audit.md](security_page_audit.md). No deben publicarse en la
página hasta tener evidencia.

## Comandos

```sh
# Crea o actualiza la página y sincroniza la ruta /security -> /seguridad.
bin/rails yogasto:setup_security_page

# Reemplaza las secciones de contenido desde el tema (sobrescribe ediciones).
FORCE=1 bin/rails yogasto:setup_security_page

# Crea la página sin publicar.
PUBLISH=0 bin/rails yogasto:setup_security_page
```

## Pruebas

```sh
bin/rails test test/integration/public_cms_security_page_test.rb
bin/rails test test/system/security_page_test.rb
```
