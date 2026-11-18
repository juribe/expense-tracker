# SEO y GEO del sitio público

El contenido público de marketing se administra en **Maglev CMS**. No hay un
segundo sistema de contenido: las páginas, secciones, metadatos y enlaces se
editan en Maglev y se publican con el flujo normal del editor.

## Arquitectura

- Tema: `app/theme/theme.yml` y `app/theme/sections/`.
- Vistas: `app/views/theme/sections/`.
- Layout público: `app/views/theme/layout.html.erb`.
- Metadatos y JSON-LD: `app/helpers/maglev_theme_helper.rb` y
  `app/helpers/public_cms_seo_helper.rb`.
- Sitemap: `GET /sitemap` y `GET /sitemap.xml`
  (`PublicCms::SitemapController`).
- Contenido editorial del Centro de ayuda: `db/seeds/help_center.rb`.
- Catálogo SEO y landing pages: `db/seeds/seo_content.rb`.

## URLs públicas

- `/`: home de marketing.
- `/precios`: planes y precios (aplicación principal, no Maglev).
- `/funciones/app-para-controlar-gastos`
- `/funciones/registrar-gastos-por-whatsapp`
- `/funciones/importar-gastos-desde-gmail`
- `/funciones/asistente-financiero-con-ia`
- `/finanzas-personales-colombia`
- `/ayuda`, `/ayuda/<categoria>`, `/ayuda/<categoria>/<articulo>`
- `/privacidad`, `/terminos-y-condiciones`, `/seguridad`,
  `/eliminacion-de-datos`, `/contact`.

Las URLs de los artículos existentes del Centro de ayuda no cambian.

## Comandos

```sh
# Aplica todo el contenido público versionado después de un despliegue.
# Crea el sitio si falta, siembra el Centro de ayuda cuando es necesario,
# refresca artículos y landing pages, y publica solo lo que cambió.
bin/rails yogasto:deploy_cms_content

# Crea o actualiza los cinco artículos SEO, las cinco landing pages y los
# enlaces internos de la home y el footer. Es idempotente.
bin/rails yogasto:setup_seo_content

# Crea páginas nuevas definidas en el tema (no sobrescribe contenido).
bin/rails yogasto:sync_cms_pages

# Reconstruye el índice de búsqueda del Centro de ayuda.
bin/rails yogasto:reindex_help_center
```

## Metadatos

Cada página publicada expone:

- `seo_title` y `meta_description` únicos.
- Un H1 en la cabecera de la página.
- Canonical HTTPS en `PUBLIC_SITE_URL` (por defecto `https://yogasto.co`).
- `og:title`, `og:description`, `og:url` y Twitter Card.
- `meta_robots` con `index,follow` en las páginas públicas.

`PUBLIC_SITE_URL` permite cambiar el origen canónico en otros entornos sin
modificar el contenido:

```sh
export PUBLIC_SITE_URL="https://yogasto.co"
```

## Datos estructurados

El layout público renderiza JSON-LD una sola vez por entidad:

- `Organization` y `WebSite` en todas las páginas Maglev.
- `SoftwareApplication` con `applicationCategory: FinanceApplication`,
  `operatingSystem: Web`, moneda COP y ofertas reales del Payment Engine.
- `BreadcrumbList` en páginas que no son la home.
- `Article` + `TechArticle` en artículos editoriales del Centro de ayuda.

No se publican reseñas, calificaciones ni FAQPage inventadas.

## Sitemap y robots

`/sitemap` incluye páginas Maglev publicadas, visibles y sin `noindex`, más
`/precios`. Excluye borradores, páginas ocultas, páginas legales retiradas y
recursos privados de la aplicación. Todas las URLs usan HTTPS y el host
canónico.

`public/robots.txt` permite el rastreo y declara:

```text
Sitemap: https://yogasto.co/sitemap
```

## Contenido nuevo

La sección Maglev **Contenido de landing** (`landing_content`) permite editar
encabezados, párrafos, listas, consejos y ejemplos sin tocar ERB. Se usa en las
páginas comerciales y mantiene la jerarquía H2/H3 debajo del H1 del hero.
