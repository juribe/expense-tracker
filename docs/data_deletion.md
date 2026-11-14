# Eliminación de datos

La página pública vive en `/eliminacion-de-datos` y se administra desde Maglev.
Reutiliza la sección **Documento legal** compartida con la Política de privacidad
y los Términos y condiciones.

## Administración

En Maglev, abrir la página **Eliminación de datos**
(`eliminacion-de-datos`) y editar la sección **Documento legal**:

- Cada bloque raíz `Sección de la política` es un apartado con ancla, título,
  etiqueta de índice, introducción y contenido.
- Dentro de cada sección se pueden añadir textos, listas, grupos de tarjetas y
  avisos.
- El índice lateral se genera desde los bloques raíz; agregar, eliminar,
  renombrar o reordenar secciones actualiza el índice.
- La fecha de actualización, el tiempo de lectura, las migas de pan, el aviso
  introductorio y el CTA son ajustes de la sección.

## Estado actual

La página está publicada con `index,follow` y se incluye en el sitemap cuando
está publicada. Los enlaces de acceso son:

- El footer compartido del sitio público (Maglev).
- El footer del layout de precios (`app/views/shared/_footer.html.erb`).
- La tarjeta de cancelación de cuenta en `Perfil`.

En un sitio Maglev ya existente, el footer conserva el contenido guardado en la
base de datos. La tarea `yogasto:link_data_deletion_in_footer` agrega el enlace
a la columna **Confianza y legal** sin reemplazar el resto del contenido y
refresca el footer publicado. Las instalaciones nuevas lo reciben desde el tema.
La Política de privacidad enlaza esta página cuando se vuelve a ejecutar su
semilla con `FORCE=1`.

El bloque **Columna** del footer declara `accept: [link]`, por lo que el editor
permite agregar enlaces dentro de las columnas. Antes de ese ajuste la interfaz
solo mostraba las columnas raíz y no ofrecía el botón para agregar un enlace
hijo.

La ruta no reemplaza la baja de la cuenta: solo explica el procedimiento y los
canales de solicitud.

## Afirmaciones verificadas

- La cuenta se elimina desde `Perfil`, con contraseña actual, confirmación
  `ELIMINAR` y, si está activo, TOTP o un código de recuperación
  (`app/controllers/users/registrations_controller.rb`).
- La eliminación destruye el usuario y los registros asociados configurados con
  `dependent: :destroy` en `app/models/user.rb`, incluidos movimientos,
  cuentas, presupuestos, metas, integraciones y telemetría de IA.
- Las identidades de WhatsApp se conservan con `dependent: :nullify`; el
  vínculo con la cuenta se elimina, pero el número puede permanecer como
  identificador para evitar que se vincule a otra cuenta sin autorización.
- Las copias de seguridad pueden conservar versiones anteriores durante su
  ciclo de rotación; la política de privacidad ya describe ese comportamiento y
  no promete borrado inmediato.
- Los plazos de consultas y reclamos corresponden a la Ley 1581 de 2012 y
  coinciden con la Política de privacidad.
- Yogasto no almacena el número completo de las tarjetas; ePayco procesa los
  pagos con sus propias políticas.

## Pendiente de decisión

- Definir el procedimiento interno para verificar solicitudes de eliminación
  enviadas por correo (qué evidencia se solicita, quién responde y cómo se
  registra la solicitud).
- Confirmar el periodo de conservación de copias de seguridad en producción y
  el procedimiento para eliminar identificadores seudonimizados a solicitud.
- Validar legalmente el texto con revisión legal antes de usarlo como respuesta
  formal a una autoridad o plataforma externa.

Estos pendientes no se publican en la página.

## Comandos

```sh
# Crea o actualiza la página pública y la publica con index,follow.
bin/rails yogasto:setup_data_deletion

# Recrea el contenido desde la semilla (sobrescribe ediciones).
FORCE=1 bin/rails yogasto:setup_data_deletion

# Crea la página sin publicar.
PUBLISH=0 bin/rails yogasto:setup_data_deletion

# Agrega el enlace al footer del sitio sin borrar el contenido existente.
bin/rails yogasto:link_data_deletion_in_footer
```

La semilla está en `db/seeds/data_deletion.rb`. Después de la primera creación,
la fuente de verdad es el contenido almacenado en Maglev.

## Deploy temporal

Mientras la página y el enlace no se administren desde el editor,
`.github/workflows/deploy.yml` ejecuta después de `kamal setup`:

```sh
bin/rails yogasto:setup_data_deletion
bin/rails yogasto:link_data_deletion_in_footer
```

Ambas tareas son idempotentes y conservan el contenido editado. Eliminar esos
dos pasos del workflow cuando la página y el enlace estén verificados en
producción. La prueba `test/lib/deploy_workflow_test.rb` protege la presencia de
ambos comandos.

## Pruebas

```sh
bin/rails test test/integration/public_cms_data_deletion_test.rb
bin/rails test test/integration/public_cms_institutional_pages_test.rb
```
