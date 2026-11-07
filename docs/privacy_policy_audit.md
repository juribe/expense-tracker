# Auditoría de la política de privacidad

Fecha de revisión: 7 de noviembre de 2026.

Este informe es interno. Recoge la evidencia usada para corregir la política
pública y los pendientes que requieren una decisión del responsable de Yogasto.
No debe publicarse en `/privacidad` ni sustituye una revisión legal.

## Alcance y método

- Se revisó la semilla `db/seeds/privacy_policy.rb`, el contenido almacenado en
  Maglev y la página pública `/privacidad`.
- Se revisaron los modelos, servicios, trabajos, configuración y pruebas
  relacionados con proveedores, conservación, cookies, telemetría, correos,
  derechos y menores.
- Se contrastaron los plazos de derechos con la Ley 1581 de 2012, artículos 14
  y 15, y los datos mínimos del responsable con el artículo 13 del Decreto 1377
  de 2013.
- No se inventaron periodos, regiones, garantías, mecanismos de verificación ni
  condiciones de proveedores. Cuando no hubo evidencia, el punto quedó en este
  informe.

## 1. Información del responsable

Publicado en la política:

- Nombre o razón social: José Uribe.
- Domicilio: Soledad, Atlántico, Colombia.
- Correo electrónico y canal de privacidad: `hola@yogasto.co`.

Cambios aplicados:

- Se retiraron la dirección residencial exacta y el teléfono personal.
- No se publica número de cédula ni NIT.

Pendiente de decisión:

- Confirmar que José Uribe es la persona natural que opera Yogasto y que el
  domicilio publicado es el que corresponde legalmente.
- Evaluar con revisión legal si el artículo 13 del Decreto 1377 de 2013 exige
  publicar una dirección y un teléfono. Si se requiere, definir una dirección y
  un canal de contacto legales que no expongan la vivienda ni el teléfono
  personal del responsable.

## 2. Proveedores tecnológicos

Proveedores que quedaron publicados:

| Proveedor | Función | Evidencia |
| --- | --- | --- |
| OVHcloud | Infraestructura y alojamiento en Canadá | Confirmado por el responsable en la solicitud de actualización. |
| ePayco | Procesamiento de pagos | `payment_engine/lib/payment_engine/providers/epayco.rb` y cliente asociado. |
| Mistral | Inteligencia artificial | Proveedor fuerte por defecto y `MISTRAL_API_KEY` configurada en el entorno local. |
| OpenRouter | Inteligencia artificial alternativa | `AI_CHEAP_PROVIDER=openrouter` en el entorno local y cliente en `app/services/ai/providers/open_router.rb`. |
| Google / Gmail | Integración de correo | Conexión OAuth y servicios en `app/services/gmail/` y `app/models/gmail_connection.rb`. |
| Meta / WhatsApp | Mensajería | Webhook y servicios en `app/controllers/webhooks/whatsapp_controller.rb` y `app/services/whatsapp/`. |
| Cloudflare | Procesamiento de correo entrante | `MAIL_INBOUND_PROVIDER=cloudflare` en el entorno local y proveedor en `app/services/mail_inbound/providers/cloudflare.rb`. |

Proveedores retirados de la página pública:

- Flex AI: existe un cliente en `app/services/ai/providers/flex_ai.rb`, pero no
  aparece configurado en el entorno local.
- Resend: existe el gem y el proveedor de correo entrante, pero el entorno local
  usa Cloudflare.

Pendientes de verificación:

- Confirmar la configuración real de producción. Si Flex AI o Resend están
  activos en producción, deben volver a la lista pública.
- Verificar el DPA de OVHcloud y las garantías aplicables a la transferencia
  internacional de datos personales desde Colombia hacia Canadá.
- Verificar los enlaces públicos de privacidad, regiones de tratamiento,
  retención y acuerdos de tratamiento de cada proveedor.
- Verificar si OVHcloud, Cloudflare, Google Fonts u otro servicio del entorno de
  producción incorporan cookies, registros o tratamientos adicionales.
- Confirmar si las fuentes de Google cargadas por la interfaz deben divulgarse
  como proveedor o si se alojan localmente.

## 3. Conservación de información

Evidencia revisada:

- Eliminación de cuenta: `app/models/user.rb` define eliminación en cascada para
  movimientos, cuentas, integraciones, telemetría de IA y la mayoría de registros
  del usuario. Las identidades de WhatsApp se conservan con `dependent: :nullify`.
- Telemetría de IA: `app/models/ai_request.rb` cifra el prompt y la salida; las
  filas se eliminan con el usuario.
- Correos procesados: `app/models/processed_email.rb`,
  `app/models/mail_inbound_delivery.rb`, `app/jobs/mail_inbound_process_job.rb` y
  `app/jobs/mail_inbound_handle_job.rb` eliminan el contenido del correo al
  terminar el procesamiento o tras un fallo definitivo.
- Limpieza adicional: `app/services/mail_inbound/content_purger.rb` limpia
  contenido antiguo de forma manual/controlada; no está programada en
  `config/recurring.yml`.
- Logs de aplicación: producción escribe en STDOUT
  (`config/environments/production.rb`); no hay un periodo de retención
  configurado en la aplicación.
- Backups: la tarea `db:backup` y `script/db_backup.sh` usan 14 días por defecto,
  pero corresponden al respaldo de la base de datos de desarrollo. No se tomó ese
  valor como periodo de producción de OVHcloud.
- Solid Queue elimina trabajos terminados cada hora en producción
  (`config/recurring.yml`). Solid Cable conserva mensajes 1 día
  (`config/cable.yml`).

La política pública ahora indica que las copias de respaldo pueden conservar
versiones anteriores y que la eliminación de la cuenta no implica su borrado
inmediato. No se publicó un número de días.

Pendientes de decisión:

- Definir y documentar el periodo real de conservación de cuentas y datos
  financieros.
- Definir el periodo de retención de la telemetría de IA.
- Definir el periodo de retención de logs de aplicación y de infraestructura.
- Definir el periodo de conservación de correos, archivos, imágenes y audios
  procesados.
- Confirmar el periodo de retención de los backups automáticos de OVHcloud y el
  procedimiento de rotación.
- Validar legalmente el texto de conservación y la relación entre eliminación de
  cuenta, registros activos y copias de respaldo.

## 4. Derechos y solicitudes

Publicado:

- Canal: `hola@yogasto.co`.
- Consultas: diez (10) días hábiles, prorrogables por cinco (5) días hábiles.
- Reclamos: quince (15) días hábiles, prorrogables por ocho (8) días hábiles.
- Referencia legal: Ley 1581 de 2012, artículos 14 y 15.

Pendientes de decisión:

- Validar los plazos y el procedimiento con revisión legal.
- Definir el procedimiento interno de identificación del solicitante, registro de
  solicitudes, respuesta y escalamiento.
- Confirmar que el buzón `hola@yogasto.co` está monitoreado y que existe un
  responsable interno de atender estas solicitudes.

## 5. Cookies y tecnologías similares

Evidencia revisada:

- No se encontraron cookies de analítica, publicidad ni píxeles de seguimiento
  en el código de la aplicación.
- Se usan cookies necesarias para la sesión y para el aviso de membresía
  (`app/controllers/application_controller.rb`).
- Se usa `localStorage` o `sessionStorage` para preferencias de interfaz,
  onboarding, tema visual, historial local del playground y estado de
  sincronización de Gmail.

Pendientes de verificación:

- Auditar cookies reales del entorno de producción, el CDN y los servicios
  externos.
- Confirmar si las solicitudes a Google Fonts deben divulgarse o reemplazarse por
  fuentes locales.
- Definir el mecanismo de consentimiento si en el futuro se incorporan cookies no
  necesarias.

## 6. Menores de edad

Publicado:

- Yogasto no está dirigido a menores de edad.
- No se debe crear una cuenta ni proporcionar datos sin autorización del
  representante legal.
- La aplicación no cuenta actualmente con un mecanismo automático de verificación
  de edad.

Pendientes de decisión:

- Definir la edad mínima aplicable y el tratamiento de cuentas de menores.
- Definir si se exigirá autorización del representante legal y cómo se
  verificará.
- Validar el texto con revisión legal.

## 7. Advertencias internas retiradas

Se eliminaron de la página pública, sin ocultarlas con CSS:

- El aviso “Versión preliminar en revisión legal”.
- “Confirmar antes de publicar”.
- “Pendiente de verificación”.
- “Plazos pendientes”.
- “Sin cookies publicitarias identificadas” con instrucciones internas.
- “Pendiente de confirmar” en menores.
- “Canal de privacidad” con instrucciones internas.
- Textos que hablaban del código actual o pedían validar plazos antes de
  publicar.

La evidencia de esta auditoría y los pendientes viven únicamente en este
informe. La página se publicó con `index,follow` y entra al sitemap.

## 8. Pruebas ejecutadas

```sh
bin/rails test test/integration/public_cms_privacy_policy_test.rb
bin/rails test test/system/privacy_policy_test.rb
```

Resultado: integración 7 pruebas / 49 aserciones en verde; sistema 3 pruebas /
26 aserciones en verde. Las pruebas de la política validan que la página abra,
que el índice y las secciones se rendericen y que no se expongan datos
personales innecesarios ni notas internas. No se añadieron pruebas detalladas
para cada texto informativo.
