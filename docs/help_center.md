# Centro de ayuda

El Centro de ayuda vive en `/ayuda` y se administra desde Maglev. No hay un
segundo editor de contenido: las categorías y los artículos son páginas Maglev
y el resto del sistema solo mantiene una proyección de lectura para listados,
búsqueda y valoraciones.

## URLs

- `/ayuda`: landing con buscador, categorías y preguntas populares.
- `/ayuda/<categoria>`: categoría.
- `/ayuda/<categoria>/<articulo>`: artículo.
- `/ayuda/buscar`: endpoint JSON del buscador.
- `/ayuda/valoracion`: endpoint de valoración.
- `/help`: redirección 301 a `/ayuda`.
- `/contactanos`: redirección 301 a `/contact`.

El acceso al Centro de ayuda se mantiene en el footer compartido, no en el
navbar superior.

## Crear una categoría

1. En Maglev, crear una página con path `ayuda/<categoria>`.
2. Escribir el nombre en el título de la página y completar la pestaña SEO.
3. Añadir las secciones:
   - `Cabecera de categoría`
   - `Listado de artículos`
   - `Otras categorías`
   - `Contenido institucional` (CTA a `/contact`)
4. Ajustar icono, descripción y posición en la cabecera.
5. Publicar.

La categoría aparece automáticamente en la landing y en el sitemap.

## Crear un artículo

1. En Maglev, crear una página con path `ayuda/<categoria>/<articulo>`.
2. Escribir el título del artículo y completar la pestaña SEO.
3. Añadir las secciones:
   - `Cabecera de artículo`: resumen, icono, posición, destacado/popular,
     portada opcional.
   - `Contenido de artículo`: encabezados, párrafos, imágenes, consejos,
     advertencias y enlaces a recursos.
   - `Valoración del artículo`.
   - `Artículos relacionados`: rutas separadas por línea; si se deja vacío,
     se muestran otros artículos de la misma categoría.
   - `Contenido institucional`.
4. Publicar.

Los borradores no aparecen en listados, búsqueda ni sitemap. La visibilidad se
controla con el checkbox `visible` de Maglev y la publicación con la acción de
publicar.

## Contenido enriquecido

Los párrafos admiten HTML seguro para `p`, listas, énfasis, enlaces, tablas,
imágenes y encabezados. El HTML se sanea en la vista; no se renderiza contenido
editorial sin allowlist.

## Comandos

```sh
# Crea /ayuda, las cinco categorías y los artículos iniciales. Es idempotente.
bin/rails yogasto:setup_help_center

# Solo crea contenido inicial que falte.
bin/rails yogasto:seed_help_center

# Reconstruye la proyección de lectura desde las páginas publicadas.
bin/rails yogasto:reindex_help_center

# Retira el enlace del navbar, mantiene el del footer y actualiza /help.
bin/rails yogasto:sync_help_center_navigation
```

## Índice y datos derivados

`HelpCategoryIndex` y `HelpArticleIndex` son proyecciones desechables de las
páginas Maglev publicadas. No se editan a mano. Se actualizan al guardar o
publicar una página y se pueden reconstruir con `yogasto:reindex_help_center`.

`HelpArticleRating` guarda valoraciones con un fingerprint opaco. No se almacena
la IP en claro y la respuesta pública no expone conteos internos.

## PSE

El checkout de planes permite pagar con PSE (débito bancario). La guía se
publica en la categoría Membresía y pagos. PSE es un pago manual: no crea una
suscripción automática, por lo que el siguiente periodo requiere un nuevo pago.

Para publicar la guía en una instalación donde quedó creada como borrador:

```sh
bin/rails yogasto:publish_help_center_pse
```
