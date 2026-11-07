# Seguridad

La página pública vive en `/seguridad` y se administra desde Maglev. La ruta
anterior `/security` responde con un 301 a la nueva URL.

## Administración

En Maglev, abrir la página **Seguridad** (`seguridad`). La página reutiliza el
navbar, el footer, el hero institucional y la sección de tarjetas de seguridad
que ya existe en el tema.

Secciones editables:

- **Hero institucional**: etiqueta, título, descripción, texto complementario,
  ilustración de escudo y chips flotantes.
- **Seguridad** (Nuestro compromiso): kicker, título, descripción, nota y tres
  tarjetas editables. Cada tarjeta tiene icono, visibilidad y orden.
- **Proceso de seguridad**: introducción, aviso y etapas numeradas. Se pueden
  agregar, eliminar y reordenar etapas.
- **Qué guardamos y qué no**: títulos de las columnas, elementos de cada
  columna y nota aclaratoria. El editor elige la columna de cada elemento.
- **Buenas prácticas de seguridad**: tarjetas con icono, título y descripción.
- **Preguntas frecuentes de seguridad**: pares pregunta/respuesta en un
  acordeón nativo (`details`/`summary`), accesible con teclado.
- **CTA de seguridad**: título, descripción y botón.
- **SEO de la página**: title, meta description, Open Graph y canonical.

El contenido se guarda en Maglev después de la primera carga. La semilla del
tema es solo el punto de partida.

## Afirmaciones verificadas

- La aplicación y la base de datos están alojadas en un servidor VPS de
  OVHcloud (confirmado por el responsable del producto).
- Los correos entrantes se almacenan temporalmente en `mail_inbound_deliveries`
  y `processed_emails.payload`; el contenido se purga al terminar el
  procesamiento o al agotar los reintentos.
- Los movimientos estructurados se conservan en las tablas financieras.
- Yogasto no almacena números completos ni datos completos de tarjetas. Solo
  pueden existir referencias, identificadores de transacción o los últimos
  cuatro dígitos usados para identificar un medio de pago.
- La producción fuerza HTTPS (`config.force_ssl = true`) y el footer compartido
  muestra esa condición.
- Las dependencias se mantienen actualizadas como parte del mantenimiento del
  servicio.

## Pendiente de confirmación

- Retención exacta en logs, colas, respaldos y proveedores externos.
- Política de backups y pruebas de restauración.
- Endurecimiento del servidor, monitoreo, alertas y respuesta a incidentes.
- Certificados, caducidad y configuración TLS más allá de `force_ssl`.
- Contratos y condiciones de Cloudflare, Resend, Gmail/Google, ePayco y
  proveedores de IA.
- Canal oficial para reportar incidentes de seguridad y responsable legal.
- Revisión legal de la redacción y de las afirmaciones públicas.

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
