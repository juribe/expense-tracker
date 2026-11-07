# Política de privacidad

La página pública vive en `/privacidad` y se administra desde Maglev. La ruta
anterior `/privacy` responde con un 301 a `/privacidad`.

## Administración

En Maglev, abrir la página **Política de privacidad** (`privacidad`) y editar la
sección **Política de privacidad**. El contenido se organiza como un árbol de
bloques:

- Cada bloque raíz `Sección de la política` es un apartado con ancla, título,
  etiqueta de índice y contenido.
- Dentro de cada sección se pueden añadir textos, listas, grupos de tarjetas,
  avisos y listas de proveedores.
- El índice lateral se genera automáticamente a partir de los bloques raíz. Si
  se agrega, elimina, renombra o reordena una sección, el índice se actualiza.
- Los anchors deben ser estables (`responsable`, `datos`, `ia`, etc.) para no
  romper enlaces existentes.

La fecha de actualización, el tiempo de lectura, el aviso de revisión y el CTA
son ajustes de la sección, por lo que también se editan desde Maglev.

## Estado actual

La página está publicada como **versión preliminar**:

- muestra un aviso de revisión legal;
- tiene `meta_robots = noindex,follow`;
- por eso no se incluye en el sitemap mientras esté en revisión.

Antes de considerarla definitiva, completar los datos pendientes, eliminar el
aviso de revisión y cambiar `meta_robots` a `index,follow`.

## Datos pendientes de confirmación

- Razón social, NIT y domicilio del responsable.
- Correo o canal específico de privacidad.
- Plazos de conservación y retención de respaldos.
- Edad mínima y mecanismo de verificación para menores.
- Proveedor de infraestructura, alojamiento, respaldo y monitoreo.
- Condiciones de retención, región y entrenamiento de cada proveedor de IA.
- Enlaces a las políticas de privacidad de los proveedores.
- Confirmación de cookies del entorno de producción/CDN.
- Revisión legal de los plazos y del procedimiento de derechos.

## Comandos

```sh
# Crea o actualiza la página preliminar y la publica con noindex.
bin/rails yogasto:setup_privacy_policy

# Recrea el contenido desde la semilla (sobrescribe ediciones).
FORCE=1 bin/rails yogasto:setup_privacy_policy

# Crea la página sin publicar.
PUBLISH=0 bin/rails yogasto:setup_privacy_policy
```

La semilla está en `db/seeds/privacy_policy.rb`. Después de la primera creación,
la fuente de verdad es el contenido almacenado en Maglev.
