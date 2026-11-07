# Auditoría de la página de Seguridad

Fecha de revisión: 7 de noviembre de 2026.

Este informe es interno. Recoge la evidencia usada para reescribir la página
pública de Seguridad, las medidas que no pudieron verificarse y los puntos que
requieren validación técnica o legal. No debe publicarse en `/seguridad`.

## Alcance y método

- Se revisó la página actual de Seguridad en `app/theme/theme.yml`, sus
  secciones y la documentación `docs/security_page.md`.
- Se contrastó el contenido con la Política de privacidad actualizada.
- Se revisaron autenticación, passkeys, TOTP, cifrado, CSP, HTTPS, límites de
  uso, procesamiento de correos, telemetría de IA, proveedores y backups.
- No se modificó la lógica de autenticación, infraestructura, procesamiento,
  almacenamiento, integraciones ni planes.
- No se publicaron certificaciones, auditorías independientes ni garantías
  absolutas.

## 1. Medidas verificadas

### Autenticación y cuenta

- Devise gestiona el inicio de sesión con correo y contraseña.
- Las contraseñas se almacenan mediante bcrypt, no en texto plano
  (`Gemfile.lock`, configuración de Devise).
- Passkeys: `devise-webauthn` con WebAuthn; rutas y controladores presentes.
- TOTP: `rotp` y `rqrcode`; el secreto se cifra con Active Record Encryption y
  el último paso temporal se registra para impedir reutilización.
- Los códigos de recuperación se guardan como hashes bcrypt y se muestran una
  sola vez.
- La página `Perfil > Seguridad de la cuenta` exige reautenticación con
  contraseña y responde con `Cache-Control: no-store`.
- Los desafíos WebAuthn caducan y existe protección contra reutilización.
- Hay límites de uso en login, TOTP, recuperación y configuración de seguridad.

### Protección de la información

- Producción fuerza HTTPS con `config.force_ssl = true`.
- Existe una política de seguridad de contenido (CSP) configurada.
- Las cookies se marcan como seguras al forzar SSL.
- Los tokens de Gmail, la telemetría de IA y las credenciales de proveedores se
  protegen con cifrado en reposo mediante `EncryptedSecret` / Active Record
  Encryption.
- La información de cada usuario se consulta a través de `current_user` y
  controles de autorización.
- Hay límites de uso y medidas antispam en formularios públicos y accesos
  sensibles.
- Las dependencias se actualizan como parte del mantenimiento del proyecto.

### Procesamiento

- El contenido de correos se procesa y se purga de los sistemas de
  procesamiento al terminar o tras un fallo definitivo. Si falla, puede
  conservarse mientras se reintenta.
- WhatsApp procesa únicamente los mensajes que el usuario envía a la integración
  autorizada.
- Los archivos y extractos se procesan para identificar movimientos; la carga y
  el procesamiento de extractos corresponden al plan Pro.
- La IA puede usar proveedores externos. Los proveedores activos identificados
  en la Política de privacidad son Mistral y OpenRouter.
- La telemetría de IA incluye prompts y respuestas cifrados en reposo, usados
  para diagnóstico, métricas y mejora del servicio.
- La Política de privacidad confirma que la telemetría asociada a la cuenta se
  elimina con ella.

### Infraestructura y proveedores

- OVHcloud es el proveedor de alojamiento, con infraestructura en Canadá
  (confirmado por el responsable del producto).
- ePayco procesa pagos.
- Google/Gmail y Meta/WhatsApp se usan solo cuando el usuario autoriza las
  integraciones.
- Cloudflare se usa para procesamiento de correo entrante.
- Yogasto no almacena números completos de tarjetas.
- Existen copias de seguridad automáticas para apoyar la recuperación.

## 2. Medidas que no pudieron verificarse

- Periodo exacto de retención de backups y pruebas de restauración.
- Endurecimiento del servidor, monitoreo, alertas y respuesta a incidentes.
- Configuración TLS más allá de `force_ssl` (certificados, caducidad, HSTS).
- Contratos, DPA y condiciones de retención de OVHcloud, ePayco, Mistral,
  OpenRouter, Google, Meta y Cloudflare.
- Regiones de procesamiento y uso de datos para entrenamiento de los
  proveedores de IA.
- Retención de logs de aplicación, colas y registros técnicos no asociados a la
  cuenta.
- Pruebas de penetración, auditorías independientes o certificaciones. La
  página no las afirma.
- Disponibilidad de passkeys y TOTP en producción después del despliegue y las
  migraciones. El código está implementado y las rutas existen; la página usa
  un lenguaje condicional (“cuando estén disponibles en tu cuenta”).

## 3. Contradicciones encontradas y decisiones

- La página anterior hablaba de un “servidor VPS”. Se retiró ese detalle y se
  dejó solo “infraestructura de OVHcloud ubicada en Canadá”, alineado con la
  Política de privacidad.
- La página anterior hablaba de “tablas de procesamiento”. Se reemplazó por
  “sistemas de procesamiento” para no publicar detalles internos.
- La página anterior incluía el párrafo “Una aclaración” con instrucciones
  internas sobre registros técnicos, colas y respaldos. Se eliminó.
- La página anterior presentaba solo tres medidas generales. La nueva versión
  separa protección de cuenta, protección de información, procesamiento,
  control, infraestructura y reporte de incidentes.
- La página anterior no explicaba passkeys ni TOTP. Se añadieron como métodos
  opcionales y condicionados a su disponibilidad.
- La página anterior no explicaba el procesamiento de WhatsApp, archivos ni IA.
  Se añadieron categorías alineadas con la Política de privacidad.
- La página anterior decía que el contenido del correo “se elimina” sin matices.
  La nueva versión aclara que puede conservarse mientras se reintenta un fallo.
- La página anterior no mencionaba que los backups pueden conservarse después
  del cierre de cuenta. La nueva versión lo aclara.
- La página anterior no ofrecía un canal visible para reportar incidentes. Ahora
  el CTA enlaza a `hola@yogasto.co`.

## 4. Afirmaciones eliminadas o modificadas

Se eliminaron o suavizaron:

- “Servidor VPS” y referencias a tablas internas.
- “Una aclaración” y cualquier texto de auditoría interna.
- Cualquier sugerencia de seguridad absoluta o riesgo cero.
- La idea de que todos los correos se eliminan inmediatamente.
- La idea de que todos los datos desaparecen de los backups de inmediato.

No se publicaron:

- Direcciones IP, nombres de servidores, puertos, versiones, credenciales,
  arquitectura, rutas internas ni configuraciones de red.
- Certificaciones, sellos o auditorías independientes.
- Plazos de retención de backups no confirmados.
- Nombres de proveedores no activos.

## 5. Información que requiere validación técnica

- Confirmar que passkeys y TOTP están desplegados y disponibles para los
  usuarios en producción.
- Confirmar el periodo real de retención de backups y ejecutar una prueba de
  restauración.
- Confirmar la retención de logs, colas y registros técnicos.
- Confirmar la configuración TLS completa y HSTS.
- Revisar el endurecimiento del servidor, monitoreo y respuesta a incidentes.
- Confirmar DPA, regiones y condiciones de los proveedores externos.
- Revisar la afirmación de la página de inicio sobre “Revisión de seguridad” e
  “Infraestructura actualizada”; no se modificó porque el alcance de esta tarea
  es la página `/seguridad`.
- Validar legalmente el texto público y su coherencia con la Política de
  privacidad.

## 6. Pruebas ejecutadas

```sh
bin/rails test test/integration/public_cms_security_page_test.rb
bin/rails test test/system/security_page_test.rb
```

Resultado: integración 12 pruebas / 84 aserciones en verde; sistema 3 pruebas /
18 aserciones en verde. Las pruebas validan que la página abra, las secciones
principales, passkeys/TOTP, procesamiento, backups, el canal de reporte y la
adaptación responsive.
