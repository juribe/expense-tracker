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
  introductorio y el CTA son ajustes de la sección.

## Estado actual

La página está publicada como versión pública:

- no muestra avisos de revisión ni notas internas;
- tiene `meta_robots = index,follow`;
- se incluye en el sitemap cuando está publicada.

Los términos públicos solo deben contener disposiciones verificadas y lenguaje
para usuarios. Las verificaciones legales internas y los pendientes se
documentan en
[docs/terms_and_conditions_audit.md](terms_and_conditions_audit.md).

## Datos pendientes de confirmación

Los pendientes internos no se publican en la página. La lista vigente, con la
evidencia revisada y la decisión que requiere cada punto, está en
[docs/terms_and_conditions_audit.md](terms_and_conditions_audit.md).

## Comandos

```sh
# Crea o actualiza la página pública y la publica con index,follow.
bin/rails yogasto:setup_terms_and_conditions

# Recrea el contenido desde la semilla (sobrescribe ediciones).
FORCE=1 bin/rails yogasto:setup_terms_and_conditions

# Crea la página sin publicar.
PUBLISH=0 bin/rails yogasto:setup_terms_and_conditions
```

La semilla está en `db/seeds/terms_and_conditions.rb`. Después de la primera
creación, la fuente de verdad es el contenido almacenado en Maglev.
