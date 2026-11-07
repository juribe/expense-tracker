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

La fecha de actualización, el tiempo de lectura, el aviso introductorio y el CTA
son ajustes de la sección, por lo que también se editan desde Maglev.

## Estado actual

La página está publicada como versión pública:

- no muestra avisos de revisión ni notas internas;
- tiene `meta_robots = index,follow`;
- se incluye en el sitemap cuando está publicada.

La política pública solo debe contener afirmaciones verificadas y lenguaje para
usuarios. Las verificaciones internas, los pendientes legales y las decisiones
del responsable se documentan en
[docs/privacy_policy_audit.md](privacy_policy_audit.md).

## Datos pendientes de confirmación

Los pendientes internos no se publican en la página. La lista vigente, con la
evidencia revisada y la decisión que requiere cada punto, está en
[docs/privacy_policy_audit.md](privacy_policy_audit.md).

## Comandos

```sh
# Crea o actualiza la página pública y la publica con index,follow.
bin/rails yogasto:setup_privacy_policy

# Recrea el contenido desde la semilla (sobrescribe ediciones).
FORCE=1 bin/rails yogasto:setup_privacy_policy

# Crea la página sin publicar.
PUBLISH=0 bin/rails yogasto:setup_privacy_policy
```

La semilla está en `db/seeds/privacy_policy.rb`. Después de la primera creación,
la fuente de verdad es el contenido almacenado en Maglev.
