# Catálogo de entidades financieras y reconocimiento por banco

Decisiones de la feature (2026-10-10/11) y la compatibilidad con los datos históricos.

## Decisiones principales

### 1. Catálogo global compartido
- `financial_institutions` (ya existía como catálogo del filtro de correos) se extendió con
  `slug` (identificador estable, único), `institution_type`
  (`bank / digital_bank / digital_wallet / financing_company / other`) y 56 entidades
  precargadas en `db/seed_data/financial_institutions.yml`.
- Política de seeds (`FinancialCatalogSeeder`): `slug`/`active` se fijan solo en la
  creación (los seeds **nunca reactivan** una entidad desactivada a mano);
  `aliases/domains/keywords/institution_type` son managed en cada corrida
  (el YAML es la fuente de verdad del catálogo).
- Marcas separadas de los bancos legales: Nequi/DaviPlata ganaron fila propia siguiendo el
  precedente de DAVIbank; su alias se movió de la fila del banco padre para evitar
  matches ambiguos. Palabras comunes ("dale!", "tuya", "iris", "koa", "bold") no se usan
  como alias de matching (evita falsos positivos); sus slugs/nombres siguen resolviendo
  para el selector y la migración de texto libre.

### 2. Asociación MoneySource ⇄ entidad (polimórfica)
- `money_sources.institution_type/institution_id` → `FinancialInstitution` (global) o
  `CustomFinancialInstitution` (privada del usuario). Opcional.
- Validación en el modelo: una entidad personalizada asignada a un source debe pertenecer
  al mismo usuario (`institution_belongs_to_owner`); referencias forjadas desde el form
  (`CustomFinancialInstitution:<id ajeno>`) fallan.
- La entidad NO reemplaza nombre/alias,tipo,últimos dígitos ni identificadores del source.

### 3. `bank` free text (transición)
- El campo se **conserva**: es fallback histórico y los servicios que igualaban el texto
  (`Detector`, `Match`, `statement_duplicate_detector`, enrichers, `review_builder`)
  matchean ahora por `institution_aliases` (fold del nombre/aliases de la asociación)
  con fallback al `bank` cuando no hay asociación.
- Los forms de money sources ya no piden banco a mano: usan un **autocomplete**
  (catálogo activo + entidades propias + "sin entidad") serializando
  `institution_ref = "Tipo:id"`, parseado por `MoneySource#assign_institution_ref`.
- El wizard financiero sigue escribiendo `bank` (comportamiento intacto); la asociación
  llega por el rake task o edición manual.

### 4. Cache del nombre (`institution_cached_name`)
- Columna denormalizada en `money_sources` (mismo patrón que `cached_balance`):
  escrita por `before_save` (único writer junto a las cascadas) y consultada por todas
  las vistas vía `institution_name` → **cero queries** de entidad al renderizar.
- Cascada en renombrado: `after_update` en ambas entidades actualiza el cache de sus
  sources con un `update_all` barato. Desactivar una entidad no toca el cache.
- Los `includes(:institution)` de solo-render se retiraron; los servicios que comparan
  id/tipo o aliases los conservan.

### 5. Reconocimiento: configuración por BANCO con seed source
- La configuración de nivel entidad vive en las tablas de reconocimiento existentes
  (`MoneySourceRecognition` + identificadores confirmados/sugeridos). La tabla
  `UserInstitutionSetting` creada en una iteración intermedia se **eliminó**
  (migración `DropUserInstitutionSettingsTables`).
- `/money_sources/recognition` agrupa los payment sources por entidad
  (asociación → fallback `bank` fold). Cada grupo tiene una **semilla** (el source más
  antiguo) cuyo drawer edita las señales de nivel banco (remitentes/dominios + asuntos/
  headers) más el Gmail criteria card global intacto.
- El drawer por source edita solo **keywords/last-four** (evidencia de producto).
- `SourceRecognition::Matcher`: si un grupo tiene exactamente UNA fuente configurada
  (la semilla), los hermanos no configurados usan su evidencia de banco con pesos
  compartidos más bajos (`SHARED_WEIGHTS = sender/domain 2, subject/header 1`) para que
  el banco nunca decida la tarjeta. Grupos con varias fuentes configuradas conservan el
  comportamiento legacy intacto (cero regresiones silenciosas).
- `update_recognition` reemplaza solo las secciones que llegan (ausencia de un
  parámetro = esa sección intacta; sin parámetros = solo descartes de sugerencias).
- Google `ApplyToSearchConfig` fusiona los confirmados de los sources (los del banco
  incluidos porque viven en la semilla).

### 6. Tareas controladas (no seeds): migraciones de datos personales
- `bin/rails institutions:migrate_banks` (+`DRY_RUN=1`):
  asocia cada `money_source.bank` con una entidad global/personalizada solo si el match
  fold es **inequívoco** (nombre canónico o alias); los ambiguos/sin match quedan
  sin asociar con reporte. Re-ejecutable (skips ya asociados). Original `bank`
  nunca se toca.
- `bin/rails institutions:consolidate_bank_recognition` (+`DRY_RUN=1`):
  consolida las señales de nivel banco confirmadas de todos los members de un grupo a la
  semilla y las borra de los members (sin duplicados físicos); keywords/last-four quedan
  por source; sugerencias sin revisar no se tocan. Re-ejecutable.

### 7. UI
- "Mis entidades" (`/financial_institutions`): SOLO las entidades propias agrupadas por
  tipo (renombrar/eliminar; el borrado se bloquea si aún hay sources asociados).
  El catálogo global no se lista ni se edita — aparece inline en el autocomplete del form.
- Reconocimiento: grupos por banco (contador, pendientes por revisar, "Configurar banco"),
  filas de sources, drawers duales (banco/por-source).
- "Fuente sin entidad" y efectivo funcionan igual que antes.

## Qué quedó movido (registro)

- Modelos: `FinancialInstitution(+slug/type)`, `CustomFinancialInstitution`,
  `MoneySource (asociación, cache, institution_token)`, `User (+2 asociaciones)`.
- Migraciones: slug/type catálogo, custom_financial_institutions,
  institution en money_sources, **user_institution_settings CREATE → DROP**
  (iteración intermedia retirada), institution_cached_name + backfill.
- Servicios: matcher (grupos/seed/shared), discovery (`institution_matches_source?`),
  suggestion_engine (hermanos por asociación), apply_to_search_config (revertido),
  detector/match/duplicate/enrichers/review_builder (matching con fallback),
  Institutions::BankMigrator, Institutions::BankRecognitionConsolidator.
- Controllers: money_sources (recognition agrupado, drawers duales,
  institution_ref), custom_financial_institutions, financial_institutions.
- Eliminados: UserInstitutionSetting(+Value), su controller/vistas/rutas,
  `SourceValueClassifier`, `institution_settings_link`.
- Seeds: 56 entidades (verificables; sin datos legales inventados).

## Comandos de producción (orden)

1. `bin/rails db:migrate` (incluye drop de settings si existieran)
2. `DBY_RUN=1 bin/rails institutions:migrate_banks` → revisar → correr real
3. `DRY_RUN=1 bin/rails institutions:consolidate_bank_recognition` → revisar → real
4. Re-run de ambos es seguro (idempotentes).
