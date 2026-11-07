# Términos y condiciones

La página pública vive en `/terminos-y-condiciones` y se administra desde
Maglev. La ruta anterior `/terms` responde con un 301 a la nueva URL.

## Administración

En Maglev, abrir la página **Términos y condiciones**
(`terminos-y-condiciones`) y editar la sección **Documento legal**, compartida
con la Política de privacidad.

- Cada bloque raíz `Sección de la política` es un apartado con ancla, título,
  número, etiqueta de índice y contenido.
- Dentro de cada sección se pueden añadir textos, listas, grupos de tarjetas,
  avisos y listas de proveedores.
- El índice lateral se genera desde los bloques raíz; agregar, eliminar,
  renombrar o reordenar secciones actualiza el índice.
- La fecha de actualización, el tiempo de lectura, las migas de pan, el aviso
  de revisión y el CTA son ajustes de la sección.

## Estado actual

La página está publicada como **versión preliminar**:

- muestra un aviso de revisión legal;
- tiene `meta_robots = noindex,follow`;
- por eso no se incluye en el sitemap mientras esté en revisión.

Antes de considerarla definitiva, completar los datos pendientes, eliminar el
aviso de revisión y cambiar `meta_robots` a `index,follow`.

## Datos pendientes de confirmación

- Titular legal, razón social, NIT y domicilio.
- Correo oficial y canal de reclamaciones.
- Edad mínima y requisitos de capacidad legal.
- Condiciones definitivas de membresías, vencimiento y acceso posterior.
- Reglas de renovación anticipada y disponibilidad del plan Gratis.
- Condiciones de reembolsos, reversiones, facturación y disputas.
- Medios de pago definitivos y tratamiento de pagos pendientes/rechazados.
- Proveedores externos y sus condiciones aplicables.
- Jurisdicción, mecanismos de atención de reclamaciones y revisión legal de
  protección al consumidor.

## Comandos

```sh
# Crea o actualiza la página preliminar y la publica con noindex.
bin/rails yogasto:setup_terms_and_conditions

# Recrea el contenido desde la semilla (sobrescribe ediciones).
FORCE=1 bin/rails yogasto:setup_terms_and_conditions

# Crea la página sin publicar.
PUBLISH=0 bin/rails yogasto:setup_terms_and_conditions
```

La semilla está en `db/seeds/terms_and_conditions.rb`. Después de la primera
creación, la fuente de verdad es el contenido almacenado en Maglev.
