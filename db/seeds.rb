# frozen_string_literal: true

# Default expense categories — shared across all users
# Source: expense_tracker_categorias_tags_revisado.csv
EXPENSE_CATEGORY_SEEDS = [
  { name: 'Mercado', tags: ['mercado', 'supermercado', 'tienda', 'fruver', 'frutas', 'verduras', 'carne', 'pollo', 'pescado', 'arroz', 'leche', 'huevos', 'alimentos', 'despensa'] },
  { name: 'Restaurantes y cafés', tags: ['restaurante', 'restaurantes', 'cafetería', 'cafe', 'almuerzo', 'desayuno', 'brunch', 'cena', 'comida fuera', 'mesa', 'propina'] },
  { name: 'Domicilios y antojos', tags: ['domicilio', 'domicilios', 'delivery', 'pedido de comida', 'comida rápida', 'hamburguesa', 'pizza', 'perro caliente', 'snack', 'mecato', 'antojo', 'postre', 'helado'] },
  { name: 'Vivienda y básicos', tags: ['arriendo', 'alquiler', 'hipoteca', 'cuota vivienda', 'administración', 'conjunto', 'predial', 'reparación', 'plomería', 'electricista', 'limpieza', 'detergente'] },
  { name: 'Hogar y mejoras', tags: ['mueble', 'electrodoméstico', 'decoración', 'adornos', 'utensilios', 'olla', 'vajilla', 'organización', 'estantería', 'mejora hogar'] },
  { name: 'Servicios y comunicaciones', tags: ['energía', 'luz', 'electricidad', 'agua', 'acueducto', 'alcantarillado', 'gas', 'internet', 'wifi', 'telefonía', 'celular', 'recarga', 'televisión', 'tv'] },
  { name: 'Transporte', tags: ['combustible', 'gasolina', 'diésel', 'bus', 'transmetro', 'transporte público', 'peaje', 'parqueadero', 'parqueo', 'mantenimiento vehículo', 'repuesto', 'llanta', 'soat', 'tecnomecánica'] },
  { name: 'Taxis y apps', tags: ['uber', 'didi', 'cabify', 'taxi', 'taxi aeropuerto', 'plataforma transporte', 'viaje en app', 'servicio de transporte'] },
  { name: 'Salud', tags: ['médico', 'consulta', 'especialista', 'examen', 'laboratorio', 'medicamento', 'farmacia', 'eps', 'medicina prepagada', 'odontología', 'dentista', 'gafas', 'terapia', 'urgencias'] },
  { name: 'Cuidado personal', tags: ['gimnasio', 'entrenador', 'masaje', 'spa', 'peluquería', 'barbería', 'manicure', 'pedicure', 'cosmética bienestar', 'suplemento nutricional'] },
  { name: 'Ocio y salidas', tags: ['cine', 'concierto', 'teatro', 'bar', 'discoteca', 'salida', 'evento', 'parque', 'espectáculo', 'videojuego', 'hobby', 'museo', 'exposición', 'actividad recreativa'] },
  { name: 'Suscripciones', tags: ['netflix', 'spotify', 'disney', 'prime video', 'streaming', 'suscripción', 'membresía digital', 'icloud', 'google one', 'software personal', 'app premium'] },
  { name: 'Compras necesarias', tags: ['ropa necesaria', 'uniforme', 'zapatos necesarios', 'artículo personal básico', 'reposición necesaria', 'producto higiene'] },
  { name: 'Gustos y compras', tags: ['compra impulsiva', 'ropa', 'calzado', 'accesorios', 'joyería', 'reloj', 'perfume', 'maquillaje', 'compra online', 'mercado libre', 'antojo de compra'] },
  { name: 'Educación', tags: ['colegio', 'matrícula', 'pensión escolar', 'universidad', 'curso', 'idiomas', 'certificación', 'libro académico', 'útiles', 'material de estudio', 'tutoría'] },
  { name: 'Viajes', tags: ['viaje', 'vacaciones', 'vuelo', 'tiquete aéreo', 'hotel', 'alojamiento', 'airbnb', 'hostal', 'tour', 'excursión', 'turismo', 'maleta', 'seguro de viaje', 'viaje internacional'] },
  { name: 'Familia', tags: ['hijos', 'colegio hijos', 'mesada', 'transporte escolar', 'niñera', 'guardería', 'apoyo familiar', 'adulto mayor', 'ropa hijos', 'actividad extracurricular'] },
  { name: 'Mascotas', tags: ['mascota', 'perro', 'gato', 'concentrado', 'alimento mascota', 'veterinario', 'vacuna veterinaria', 'desparasitación', 'arena gato', 'juguete mascota'] },
  { name: 'Deudas y cuotas', tags: ['cuota crédito', 'préstamo', 'crédito consumo', 'hipoteca', 'cuota vehículo', 'pago tarjeta', 'intereses', 'cuota de manejo', 'comisión bancaria', '4x1000', 'seguro deudor'] },
  { name: 'Abonos a capital', tags: ['abono a capital', 'pago anticipado', 'prepago crédito', 'abono extraordinario', 'reducción de capital'] },
  { name: 'Seguros', tags: ['seguro', 'póliza', 'seguro de vida', 'seguro salud', 'seguro hogar', 'todo riesgo', 'seguro vehículo', 'seguro mascota', 'asistencia'] },
  { name: 'Impuestos y trámites', tags: ['impuesto', 'predial', 'impuesto vehicular', 'renta', 'declaración de renta', 'pasaporte', 'notaría', 'autenticación', 'certificado', 'abogado', 'trámite', 'comparendo', 'multa'] },
  { name: 'Trabajo', tags: ['equipo trabajo', 'computador laboral', 'monitor', 'teclado', 'software profesional', 'licencia', 'coworking', 'oficina', 'papelería', 'curso profesional', 'conferencia', 'gasto reembolsable'] },
  { name: 'Donaciones y regalos', tags: ['donación', 'fundación', 'ayuda económica', 'regalo', 'cumpleaños', 'navidad', 'boda', 'colecta', 'aporte voluntario'] },
  { name: 'Otros', tags: ['otro gasto', 'gasto no identificado', 'ajuste', 'dinero perdido', 'gasto sin categoría', 'pendiente de clasificar'] },
].freeze

EXPENSE_CATEGORY_SEEDS.each do |attrs|
  category = Category.find_or_initialize_by(name: attrs[:name], is_default: true, category_type: "expense")
  category.tags = attrs[:tags]
  category.save!
end

INCOME_DEFAULTS = I18n.t("categories.defaults.income").freeze

INCOME_DEFAULTS.each do |name|
  Category.find_or_create_by!(name: name, is_default: true, category_type: "income")
end

# Financial email catalog: Colombian institutions, global financial keywords
# and subject patterns (idempotent upserts).
require_relative "seed_data/financial_catalog_seeder"
FinancialCatalogSeeder.run
