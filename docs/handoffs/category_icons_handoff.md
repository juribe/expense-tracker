# Handoff: Iconos por categoría (`categories.icon`)

> **Estado: implementado** (migración `20261028000000`, seeds actualizadas, helper + UI mínima, tests en verde). Este documento queda como referencia del diseño y de la asignación de iconos.

## Objetivo

Cada categoría (default y personalizada) debe tener un campo `icon` (texto) con la clase de su icono
(`ti-*`, el font que ya usa la app). Los iconos se muestran junto al nombre de la categoría en badges,
listas y pickers. Las categorías default fijas reciben un icono semántico asignado (tabla más abajo);
toda categoría nueva (creada por el usuario) recibe por defecto el icono estándar `ti-tag`.

**No reescribas lo que ya funciona.** Implementa solo lo listado aquí. Sigue las Mandatory Skills del
proyecto (Rails, Ruby, TDD/Minitest). Antes de terminar: `bin/rails test` en verde, RuboCop limpio en
los archivos tocados, y `graphify update .` al final.

---

## 1. Hechos verificados (no re-derivar)

- **Modelo:** `app/models/category.rb` — `Category < ApplicationRecord`. PK UUID. Campos actuales
  (`db/schema.rb` líneas 91–110): `name`, `description`, `parent_id`, `active`, `user_id`,
  `is_default`, `category_type` (`%w[income expense]`), `expenses_count`, `tags` (jsonb),
  `savings_potential`, `suggested_savings_percentage`. Validaciones de unicidad/nombres en el modelo.
- **Seeds:** `db/seeds.rb`
  - `EXPENSE_CATEGORY_SEEDS` (líneas 5–31): 28 categorías gasto default con
    `name / savings_potential / suggested_savings_percentage / tags`. El upsert es idempotente:
    `find_or_initialize_by(name:, is_default: true, category_type: "expense")` + asignación +
    `save!` (líneas 33–39). **Correr los seeds actualiza categorías default ya existentes** —
    eso nos sirve para backfill.
  - Categorías ingreso default se crean desde `I18n.t("categories.defaults.income")`
    (líneas 41–45), definido en `config/locales/es.yml` (líneas 386–392):
    Salario, Trabajo independiente, Inversiones, Negocio, Regalos, Otros.
    (`config/i18n` default locale = `:es`; en `en.yml` NO existe esa llave.)
- **Iconos:** la app usa el font de iconos vendorizado por el tema Spike en
  `app/assets/vendor/themes/spike.css`: prefijo de clase `ti` (`<i class="ti ti-name">`).
  Es el set **Tabler Icons** (no el Themify clásico) — mismos nombres que Tabler. El catálogo
  disponible es exactamente el de ese archivo: no asumas nombres que no aparezcan ahí
  (verificados: todos los asignados abajo existen en `spike.css`).
  Ejemplos ya en uso: `app/helpers/application_helper.rb` (`source_kind_icon`: `building-bank`,
  `credit-card`, `cash`, `wallet`, `pig-money`, `coin`), `budgets_helper.rb`, `reconciliations_helper.rb`.
- **Puntos de UI donde aparecen categorías hoy (sin icono):**
  `app/helpers/application_helper.rb#category_badge` (líneas 94–99),
  `app/views/categories/index.html.erb` (usa `category_badge`),
  `app/views/categories/show.html.erb`, `app/views/categories/_form.html.erb`.
- **Tests relacionados:** `test/models/category_catalog_test.rb` (valida que las seeds declaren
  porcentajes; mismo patrón para extender a iconos), `test/models/category_test.rb`,
  `test/poro/category_option*_test.rb`.
- Última migración en `db/migrate/`: `20261027*`. La migración previa de categorías
  (`20261016000001_..._add_tags.rb`) muestra el estilo esperado (`ActiveRecord::Migration[8.0]`).

---

## 2. Asignación de iconos (aprobada — usar tal cual)

Cualquier categoría **nueva** (custom) sin icono explícito usa `ti-tag` (icono "label").
Entre defaults, icono único por nombre; `Otros` comparte `ti-dots` en gasto e ingreso a propósito.

### Gastos (`EXPENSE_CATEGORY_SEEDS`)

| Categoría | Clase `ti` | Racional |
|---|---|---|
| Mercado | `ti-shopping-cart` | Supermercado |
| Restaurantes y cafés | `ti-chef-hat` | Comer fuera |
| Domicilios y antojos | `ti-truck-delivery` | Delivery |
| Vivienda y básicos | `ti-home` | Arriendo/vivienda |
| Hogar y mejoras | `ti-sofa` | Muebles/electrodomésticos |
| Servicios y comunicaciones | `ti-plug` | Luz, agua, gas, internet |
| Transporte | `ti-car` | Vehículo propio/combustible |
| Taxis y apps | `ti-directions` | Trayectos en app |
| Salud | `ti-stethoscope` | Médico, farmacia, EPS |
| Cuidado personal | `ti-yoga` | Gimnasio, spa, bienestar |
| Ocio y salidas | `ti-ticket` | Cine, conciertos, bares |
| Suscripciones | `ti-repeat` | Cobros recurrentes digitales |
| Compras necesarias | `ti-shirt` | Ropa/uniformes necesarios |
| Gustos y compras | `ti-diamond` | Compras por antojo/lujos |
| Educación | `ti-school` | Colegio, universidad, cursos |
| Viajes | `ti-plane` | Vuelos, hoteles |
| Familia | `ti-baby-carriage` | Hijos, niñera, mesadas |
| Mascotas | `ti-paw` | Veterinaria, mascotas |
| Deudas y cuotas | `ti-file-invoice` | Pagarés/cuotas |
| Abonos a capital | `ti-circle-minus` | Reducir saldo pendiente |
| Seguros | `ti-shield` | Pólizas y coberturas |
| Impuestos y trámites | `ti-receipt-tax` | Impuestos, notaría, multas |
| Trabajo | `ti-briefcase` | Equipo/licencias laborales |
| Donaciones y regalos | `ti-gift` | Regalar/aportar |
| Otros | `ti-dots` | Sin categoría clara |

### Ingresos

| Categoría | Clase `ti` | Racional |
|---|---|---|
| Salario | `ti-cash-banknote` | Nómina |
| Trabajo independiente | `ti-tool` | Freelance |
| Inversiones | `ti-trending-up` | Rendimientos |
| Negocio | `ti-building-store` | Ventas de negocio |
| Regalos | `ti-gift-card` | Regalos recibidos (distinto del `ti-gift` de gasto) |
| Otros | `ti-dots` | Igual que "Otros" de gasto |

Regla: el valor en BD es la clase **sin prefijo** cuando coincida con el patrón del código existente
(`source_kind_icon` devuelve `"cash"`, la vista arma `ti ti-#{...}`), o la clase **completa**
(`"ti-cash"`) si el nuevo helper la usa entera. Para no mezclar estilos, en esta feature se guarda la
**clase completa** (`"ti-shopping-cart"`) y el helper la aplica directo: `class: "ti #{category.icon}"`.

---

## 3. Plan de implementación (TDD)

### Fase 1 — Migración + modelo (+ tests primero)

1. Escribir tests que fallen:
   - `test/models/category_test.rb`:
     - `Category.create!(name: "Nueva", category_type: "expense").icon == "ti-tag"`
       (default estándar para nuevas categorías).
     - Validación: `.new(name: "X", icon: "no-existe")` → inválida;
       `icon: "ti-star"` (o cualquier `ti-[a-z0-9-]+`) → válida; `nil` → válida (no rompe datos legados).
2. Migración (`bin/rails g migration AddIconToCategories icon:string`):
   - `add_column :categories, :icon, :string` (nullable; sin default a nivel de BD, ver abajo).
   - Índice: no se necesita (no filtra por icono).
   - Reversible: usar `def change` con `add_column` simple.
3. Modelo:
   - No agregar `presence: true` a `icon` (existen categorías creadas antes del backfill y muchos
     factories/tests crean `Category` sin icono; exigir presencia rompería la suite).
   - Agregar solo el formato: `validates :icon, format: { with: /\Ati-[a-z0-9-]+\z/ }, allow_nil: true`.
   - Default estándar para nuevas: `before_validation { self.icon ||= "ti-tag" }`.
     Así el default vive en Ruby (editable) y la columna sigue nullable para datos históricos.
4. Correr `bin/rails db:migrate` y los tests de Fase 1.

**Regla de helper/fallback (fuente de render):** ningún request debe fallar por un `icon` nil o
malformado. El helper (Fase 3) resuelve: `category.icon.presence || "ti-tag"`.

### Fase 2 — Seeds + backfill (+ tests primero)

1. Extender `test/models/category_catalog_test.rb` (mismo patrón que `EXPECTED_PERCENTAGES`):
   - Constante `EXPECTED_ICONS` (la tabla de arriba) para gastos y otra para ingresos, o un solo merge.
   - Test A: toda entrada de `EXPENSE_CATEGORY_SEEDS` declara `icon:` (como hace con
     `suggested_savings_percentage`).
   - Test B: tras correr seeds, cada default persistido tiene el icono esperado.
2. Seeds:
   - Agregar `icon:` a cada entrada de `EXPENSE_CATEGORY_SEEDS` (tabla §2).
   - En el upsert (líneas 33–39) agregar `category.icon = attrs[:icon]`.
   - Para ingresos: reemplazar el bloque I18n (líneas 41–45) por un array explícito
     `INCOME_CATEGORY_SEEDS` con `name` + `icon` (tabla §2) y el mismo upsert idempotente
     (`find_or_initialize_by(name:, is_default: true, category_type: "income")`).
     Los nombres **no cambian**. Antes de borrar el bloque I18n, grep `categories.defaults.income`:
     solo `db/seeds.rb` lo consume (verificado), pero re-verifica.
   - El arranque CI con DB nueva (`db:prepare`) obtiene los iconos por seeds; **no duplicar el
     mapeo en la migración** (fuente única de verdad = seeds).
3. **Backfill de entornos ya provisionados (deploy/dev):** correr una vez
   `bin/rails db:seed` después de `db:migrate` — el upsert de seeds ya actualiza los defaults
   existentes. Si esto no es un procedimiento estándar en el ambiente del
   agente, corre los seeds manualmente en dev y déjalo documentado abajo.
   Las categorías custom de usuario quedan con `icon = nil` → el helper las renderiza como `ti-tag`.

### Fase 3 — Helper + UI mínima

1. Test primero (ActionView::TestCase, patrón de `test/helpers/*`):
   - `category_icon_klass(category, fallback: "ti-tag")` devuelve `"ti ti-tag ..."` cuando nil;
     no arma clases si está vacío/malformado.
2. Helper (ubicación: `app/helpers/categories_helper.rb` si existe, si no `application_helper.rb`):
   ```ruby
   # Icono display para una categoría; el estándar "ti-tag" cubre
   # categorías nuevas sin icono y datos históricos con icon nulo.
   def category_icon_klass(category, fallback: "ti-tag")
     "ti #{category.icon.presence || fallback}"
   end
   ```
3. Usarlo en:
   - `category_badge` (application_helper.rb): `<i aria-hidden="true">` antes del nombre
     (mismo patrón que `money_source_badge`).
   - `app/views/categories/index.html.erb` (junto a `category_badge` en ambos bloques:
     defaults y customs).
   - `app/views/categories/show.html.erb`.
4. **No** tocar en este handoff los pickers (`CategoryPickerField/CategoryOption/CategoryOptionList`) ni
   la tabla de gastos — puede ser un segundo PR.

---

## 4. Definición de hecho (checklist)

- [ ] `add_column :categories, :icon, :string` migrado y reversible (`db:rollback` limpio).
- [ ] `Category` valida formato de icono y fija `ti-tag` en nuevas (tests en verde).
- [ ] 28 uploads de gasto + 6 ingresos de seeds llevan su icono (tabla §2), idempotente.
- [ ] `bin/rails db:seed` corrido en dev; defaults existentes quedaron con icono asignado.
- [ ] `category_badge` y vistas de categories muestran el icono; fallback nunca rompe.
- [ ] `bin/rails test` completo en verde (registrar la salida real).
- [ ] RuboCop limpio en archivos tocados.
- [ ] `graphify update .` ejecutado (salida registrada).

## 5. Fuera de alcance (no lo hagas)

- Icon-picker en el formulario de categorías / edición del icono por el usuario (separado).
- Cambiar nombres, tags, savings_potential ni cualquier dato existente de categorías.
- Migrar de font de Tabler; agregar dependencias nuevas; tocar `spike.css`.
- Cambiar los iconos de money sources / loans (`source_kind_icon`).
- Tests RSpec o cambiar configuración de prueba.
