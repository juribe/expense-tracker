# frozen_string_literal: true

# Default expense categories — shared across all users
# Source: expense_tracker_categorias_tags_revisado.csv
EXPENSE_CATEGORY_SEEDS = [
  { name: 'Mercado', savings_potential: 'low', tags: ['mercado', 'supermercado', 'tienda', 'fruver', 'frutas', 'verduras', 'carne', 'pollo', 'pescado', 'arroz', 'leche', 'huevos', 'alimentos', 'despensa'] },
  { name: 'Restaurantes y cafés', savings_potential: 'high', tags: ['restaurante', 'restaurantes', 'cafetería', 'cafe', 'almuerzo', 'desayuno', 'brunch', 'cena', 'comida fuera', 'mesa', 'propina'] },
  { name: 'Domicilios y antojos', savings_potential: 'high', tags: ['domicilio', 'domicilios', 'delivery', 'pedido de comida', 'comida rápida', 'hamburguesa', 'pizza', 'perro caliente', 'snack', 'mecato', 'antojo', 'postre', 'helado'] },
  { name: 'Vivienda y básicos', savings_potential: 'low', tags: ['arriendo', 'alquiler', 'hipoteca', 'cuota vivienda', 'administración', 'conjunto', 'predial', 'reparación', 'plomería', 'electricista', 'limpieza', 'detergente'] },
  { name: 'Hogar y mejoras', savings_potential: 'medium', tags: ['mueble', 'electrodoméstico', 'decoración', 'adornos', 'utensilios', 'olla', 'vajilla', 'organización', 'estantería', 'mejora hogar'] },
  { name: 'Servicios y comunicaciones', savings_potential: 'medium', tags: ['energía', 'luz', 'electricidad', 'agua', 'acueducto', 'alcantarillado', 'gas', 'internet', 'wifi', 'telefonía', 'celular', 'recarga', 'televisión', 'tv'] },
  { name: 'Transporte', savings_potential: 'medium', tags: ['combustible', 'gasolina', 'diésel', 'bus', 'transmetro', 'transporte público', 'peaje', 'parqueadero', 'parqueo', 'mantenimiento vehículo', 'repuesto', 'llanta', 'soat', 'tecnomecánica'] },
  { name: 'Taxis y apps', savings_potential: 'high', tags: ['uber', 'didi', 'cabify', 'taxi', 'taxi aeropuerto', 'plataforma transporte', 'viaje en app', 'servicio de transporte'] },
  { name: 'Salud', savings_potential: 'low', tags: ['médico', 'consulta', 'especialista', 'examen', 'laboratorio', 'medicamento', 'farmacia', 'eps', 'medicina prepagada', 'odontología', 'dentista', 'gafas', 'terapia', 'urgencias'] },
  { name: 'Cuidado personal', savings_potential: 'medium', tags: ['gimnasio', 'entrenador', 'masaje', 'spa', 'peluquería', 'barbería', 'manicure', 'pedicure', 'cosmética bienestar', 'suplemento nutricional'] },
  { name: 'Ocio y salidas', savings_potential: 'high', tags: ['cine', 'concierto', 'teatro', 'bar', 'discoteca', 'salida', 'evento', 'parque', 'espectáculo', 'videojuego', 'hobby', 'museo', 'exposición', 'actividad recreativa'] },
  { name: 'Suscripciones', savings_potential: 'high', tags: ['netflix', 'spotify', 'disney', 'prime video', 'streaming', 'suscripción', 'membresía digital', 'icloud', 'google one', 'software personal', 'app premium'] },
  { name: 'Compras necesarias', savings_potential: 'low', tags: ['ropa necesaria', 'uniforme', 'zapatos necesarios', 'artículo personal básico', 'reposición necesaria', 'producto higiene'] },
  { name: 'Gustos y compras', savings_potential: 'high', tags: ['compra impulsiva', 'ropa', 'calzado', 'accesorios', 'joyería', 'reloj', 'perfume', 'maquillaje', 'compra online', 'mercado libre', 'antojo de compra'] },
  { name: 'Educación', savings_potential: 'low', tags: ['colegio', 'matrícula', 'pensión escolar', 'universidad', 'curso', 'idiomas', 'certificación', 'libro académico', 'útiles', 'material de estudio', 'tutoría'] },
  { name: 'Viajes', savings_potential: 'high', tags: ['viaje', 'vacaciones', 'vuelo', 'tiquete aéreo', 'hotel', 'alojamiento', 'airbnb', 'hostal', 'tour', 'excursión', 'turismo', 'maleta', 'seguro de viaje', 'viaje internacional'] },
  { name: 'Familia', savings_potential: 'low', tags: ['hijos', 'colegio hijos', 'mesada', 'transporte escolar', 'niñera', 'guardería', 'apoyo familiar', 'adulto mayor', 'ropa hijos', 'actividad extracurricular'] },
  { name: 'Mascotas', savings_potential: 'low', tags: ['mascota', 'perro', 'gato', 'concentrado', 'alimento mascota', 'veterinario', 'vacuna veterinaria', 'desparasitación', 'arena gato', 'juguete mascota'] },
  { name: 'Deudas y cuotas', savings_potential: 'medium', tags: ['cuota crédito', 'préstamo', 'crédito consumo', 'hipoteca', 'cuota vehículo', 'pago tarjeta', 'intereses', 'cuota de manejo', 'comisión bancaria', '4x1000', 'seguro deudor'] },
  { name: 'Abonos a capital', savings_potential: 'none', tags: ['abono a capital', 'pago anticipado', 'prepago crédito', 'abono extraordinario', 'reducción de capital'] },
  { name: 'Seguros', savings_potential: 'low', tags: ['seguro', 'póliza', 'seguro de vida', 'seguro salud', 'seguro hogar', 'todo riesgo', 'seguro vehículo', 'seguro mascota', 'asistencia'] },
  { name: 'Impuestos y trámites', savings_potential: 'low', tags: ['impuesto', 'predial', 'impuesto vehicular', 'renta', 'declaración de renta', 'pasaporte', 'notaría', 'autenticación', 'certificado', 'abogado', 'trámite', 'comparendo', 'multa'] },
  { name: 'Trabajo', savings_potential: 'variable', tags: ['equipo trabajo', 'computador laboral', 'monitor', 'teclado', 'software profesional', 'licencia', 'coworking', 'oficina', 'papelería', 'curso profesional', 'conferencia', 'gasto reembolsable'] },
  { name: 'Donaciones y regalos', savings_potential: 'medium', tags: ['donación', 'fundación', 'ayuda económica', 'regalo', 'cumpleaños', 'navidad', 'boda', 'colecta', 'aporte voluntario'] },
  { name: 'Otros', savings_potential: 'por_evaluar', tags: ['otro gasto', 'gasto no identificado', 'ajuste', 'dinero perdido', 'gasto sin categoría', 'pendiente de clasificar'] },
].freeze

EXPENSE_CATEGORY_SEEDS.each do |attrs|
  category = Category.find_or_initialize_by(name: attrs[:name], is_default: true, category_type: "expense")
  category.tags = attrs[:tags]
  category.savings_potential = attrs[:savings_potential]
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
