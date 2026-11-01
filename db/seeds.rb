# frozen_string_literal: true

# Default expense categories — shared across all users
# Source: expense_tracker_categorias_tags_revisado.csv
EXPENSE_CATEGORY_SEEDS = [
  { name: 'Mercado', icon: 'ti-shopping-cart', savings_potential: 'low', suggested_savings_percentage: 5, tags: [ 'mercado', 'supermercado', 'tienda', 'fruver', 'frutas', 'verduras', 'carne', 'pollo', 'pescado', 'arroz', 'leche', 'huevos', 'alimentos', 'despensa' ] },
  { name: 'Restaurantes y cafés', icon: 'ti-chef-hat', savings_potential: 'high', suggested_savings_percentage: 10, tags: [ 'restaurante', 'restaurantes', 'cafetería', 'cafe', 'almuerzo', 'desayuno', 'brunch', 'cena', 'comida fuera', 'mesa', 'propina' ] },
  { name: 'Domicilios y antojos', icon: 'ti-truck-delivery', savings_potential: 'high', suggested_savings_percentage: 15, tags: [ 'domicilio', 'domicilios', 'delivery', 'pedido de comida', 'comida rápida', 'hamburguesa', 'pizza', 'perro caliente', 'snack', 'mecato', 'antojo', 'postre', 'helado' ] },
  { name: 'Vivienda y básicos', icon: 'ti-home', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'arriendo', 'alquiler', 'hipoteca', 'cuota vivienda', 'administración', 'conjunto', 'predial', 'reparación', 'plomería', 'electricista', 'limpieza', 'detergente' ] },
  { name: 'Hogar y mejoras', icon: 'ti-sofa', savings_potential: 'medium', suggested_savings_percentage: 5, tags: [ 'mueble', 'electrodoméstico', 'decoración', 'adornos', 'utensilios', 'olla', 'vajilla', 'organización', 'estantería', 'mejora hogar' ] },
  { name: 'Servicios y comunicaciones', icon: 'ti-plug', savings_potential: 'medium', suggested_savings_percentage: 5, tags: [ 'energía', 'luz', 'electricidad', 'agua', 'acueducto', 'alcantarillado', 'gas', 'internet', 'wifi', 'telefonía', 'celular', 'recarga', 'televisión', 'tv' ] },
  { name: 'Transporte', icon: 'ti-car', savings_potential: 'medium', suggested_savings_percentage: 5, tags: [ 'combustible', 'gasolina', 'diésel', 'bus', 'transmetro', 'transporte público', 'peaje', 'parqueadero', 'parqueo', 'mantenimiento vehículo', 'repuesto', 'llanta', 'soat', 'tecnomecánica' ] },
  { name: 'Taxis y apps', icon: 'ti-directions', savings_potential: 'high', suggested_savings_percentage: 10, tags: [ 'uber', 'didi', 'cabify', 'taxi', 'taxi aeropuerto', 'plataforma transporte', 'viaje en app', 'servicio de transporte' ] },
  { name: 'Salud', icon: 'ti-stethoscope', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'médico', 'consulta', 'especialista', 'examen', 'laboratorio', 'medicamento', 'farmacia', 'eps', 'medicina prepagada', 'odontología', 'dentista', 'gafas', 'terapia', 'urgencias' ] },
  { name: 'Cuidado personal', icon: 'ti-yoga', savings_potential: 'medium', suggested_savings_percentage: 5, tags: [ 'gimnasio', 'entrenador', 'masaje', 'spa', 'peluquería', 'barbería', 'manicure', 'pedicure', 'cosmética bienestar', 'suplemento nutricional' ] },
  { name: 'Ocio y salidas', icon: 'ti-ticket', savings_potential: 'high', suggested_savings_percentage: 10, tags: [ 'cine', 'concierto', 'teatro', 'bar', 'discoteca', 'salida', 'evento', 'parque', 'espectáculo', 'videojuego', 'hobby', 'museo', 'exposición', 'actividad recreativa' ] },
  { name: 'Suscripciones', icon: 'ti-repeat', savings_potential: 'high', suggested_savings_percentage: 15, tags: [ 'netflix', 'spotify', 'disney', 'prime video', 'streaming', 'suscripción', 'membresía digital', 'icloud', 'google one', 'software personal', 'app premium' ] },
  { name: 'Compras necesarias', icon: 'ti-shirt', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'ropa necesaria', 'uniforme', 'zapatos necesarios', 'artículo personal básico', 'reposición necesaria', 'producto higiene' ] },
  { name: 'Gustos y compras', icon: 'ti-diamond', savings_potential: 'high', suggested_savings_percentage: 15, tags: [ 'compra impulsiva', 'ropa', 'calzado', 'accesorios', 'joyería', 'reloj', 'perfume', 'maquillaje', 'compra online', 'mercado libre', 'antojo de compra' ] },
  { name: 'Educación', icon: 'ti-school', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'colegio', 'matrícula', 'pensión escolar', 'universidad', 'curso', 'idiomas', 'certificación', 'libro académico', 'útiles', 'material de estudio', 'tutoría' ] },
  { name: 'Viajes', icon: 'ti-plane', savings_potential: 'high', suggested_savings_percentage: 10, tags: [ 'viaje', 'vacaciones', 'vuelo', 'tiquete aéreo', 'hotel', 'alojamiento', 'airbnb', 'hostal', 'tour', 'excursión', 'turismo', 'maleta', 'seguro de viaje', 'viaje internacional' ] },
  { name: 'Familia', icon: 'ti-baby-carriage', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'hijos', 'colegio hijos', 'mesada', 'transporte escolar', 'niñera', 'guardería', 'apoyo familiar', 'adulto mayor', 'ropa hijos', 'actividad extracurricular' ] },
  { name: 'Mascotas', icon: 'ti-paw', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'mascota', 'perro', 'gato', 'concentrado', 'alimento mascota', 'veterinario', 'vacuna veterinaria', 'desparasitación', 'arena gato', 'juguete mascota' ] },
  { name: 'Deudas y cuotas', icon: 'ti-file-invoice', savings_potential: 'medium', suggested_savings_percentage: 0, tags: [ 'cuota crédito', 'préstamo', 'crédito consumo', 'hipoteca', 'cuota vehículo', 'pago tarjeta', 'intereses', 'cuota de manejo', 'comisión bancaria', '4x1000', 'seguro deudor' ] },
  { name: 'Abonos a capital', icon: 'ti-circle-minus', savings_potential: 'none', suggested_savings_percentage: 0, tags: [ 'abono a capital', 'pago anticipado', 'prepago crédito', 'abono extraordinario', 'reducción de capital' ] },
  { name: 'Seguros', icon: 'ti-shield', savings_potential: 'low', suggested_savings_percentage: 5, tags: [ 'seguro', 'póliza', 'seguro de vida', 'seguro salud', 'seguro hogar', 'todo riesgo', 'seguro vehículo', 'seguro mascota', 'asistencia' ] },
  { name: 'Impuestos y trámites', icon: 'ti-receipt-tax', savings_potential: 'low', suggested_savings_percentage: 0, tags: [ 'impuesto', 'predial', 'impuesto vehicular', 'renta', 'declaración de renta', 'pasaporte', 'notaría', 'autenticación', 'certificado', 'abogado', 'trámite', 'comparendo', 'multa' ] },
  { name: 'Trabajo', icon: 'ti-briefcase', savings_potential: 'variable', suggested_savings_percentage: nil, tags: [ 'equipo trabajo', 'computador laboral', 'monitor', 'teclado', 'software profesional', 'licencia', 'coworking', 'oficina', 'papelería', 'curso profesional', 'conferencia', 'gasto reembolsable' ] },
  { name: 'Donaciones y regalos', icon: 'ti-gift', savings_potential: 'medium', suggested_savings_percentage: 5, tags: [ 'donación', 'fundación', 'ayuda económica', 'regalo', 'cumpleaños', 'navidad', 'boda', 'colecta', 'aporte voluntario' ] },
  { name: 'Otros', icon: 'ti-dots', savings_potential: 'por_evaluar', suggested_savings_percentage: nil, tags: [ 'otro gasto', 'gasto no identificado', 'ajuste', 'dinero perdido', 'gasto sin categoría', 'pendiente de clasificar' ] }
].freeze

EXPENSE_CATEGORY_SEEDS.each do |attrs|
  category = Category.find_or_initialize_by(name: attrs[:name], is_default: true, category_type: "expense")
  category.tags = attrs[:tags]
  category.savings_potential = attrs[:savings_potential]
  category.suggested_savings_percentage = attrs[:suggested_savings_percentage]
  category.icon = attrs[:icon]
  category.save!
end

INCOME_CATEGORY_SEEDS = [
  { name: 'Salario', icon: 'ti-cash-banknote' },
  { name: 'Trabajo independiente', icon: 'ti-tool' },
  { name: 'Inversiones', icon: 'ti-trending-up' },
  { name: 'Negocio', icon: 'ti-building-store' },
  { name: 'Regalos', icon: 'ti-gift-card' },
  { name: 'Otros', icon: 'ti-dots' }
].freeze

INCOME_CATEGORY_SEEDS.each do |attrs|
  category = Category.find_or_initialize_by(name: attrs[:name], is_default: true, category_type: "income")
  category.icon = attrs[:icon]
  category.save!
end

# Financial email catalog: Colombian institutions, global financial keywords
# and subject patterns (idempotent upserts).
require_relative "seed_data/financial_catalog_seeder"
FinancialCatalogSeeder.run

# GMF (4x1.000) system categories
gmf_parent = Category.find_or_initialize_by(name: "Impuestos y gravámenes", is_default: true, category_type: "expense")
gmf_parent.icon = "ti-receipt-tax"
gmf_parent.save!
gmf_child = Category.find_or_initialize_by(name: "4x1.000 (GMF)", is_default: true, category_type: "expense", parent: gmf_parent)
gmf_child.icon = "ti-receipt-tax"
gmf_child.save!

# UVT values (annual) - admin can add/update via configuration
[
  { year: 2024, value: 47065.00 },
  { year: 2025, value: 49799.00 },
  { year: 2026, value: 52374.00 }
].each do |attrs|
  GmfUvtYear.find_or_create_by!(year: attrs[:year]) do |r|
    r.value = attrs[:value]
  end
end
CATEGORY_SAVING_TIPS = {
  "Mercado" => [
    { title: "Planifica la compra semanal", body: "Haz una lista antes de ir al supermercado y evita compras impulsivas." },
    { title: "Aprovecha promociones", body: "Compra productos no perecederos cuando tengan descuento." }
  ],
  "Restaurantes y cafés" => [
    { title: "Reduce comidas fuera", body: "Cocina en casa algunos días de la semana para disminuir gastos." },
    { title: "Busca menús del día", body: "Los menús ejecutivos suelen ser más económicos." }
  ],
  "Domicilios y antojos" => [
    { title: "Compara tarifas de entrega", body: "Revisa los cargos por servicio antes de confirmar el pedido." },
    { title: "Recoge el pedido directamente", body: "En algunos casos es más barato recoger que pedir domicilio." },
    { title: "Evita pedidos pequeños frecuentes", body: "Los pequeños pedidos se acumulan durante el ciclo financiero." }
  ],
  "Hogar y mejoras" => [
    { title: "Compra por necesidad", body: "Prioriza mejoras urgentes y posterga las opcionales." },
    { title: "Compara precios", body: "Revisa varias tiendas antes de comprar muebles o electrodomésticos." }
  ],
  "Servicios y comunicaciones" => [
    { title: "Revisa tus planes", body: "Cancela servicios que no uses y ajusta los planes a tu consumo real." },
    { title: "Compara proveedores", body: "Cambia de operador si encuentras una tarifa mejor." }
  ],
  "Transporte" => [
    { title: "Comparte el vehículo", body: "Compartir viajes reduce combustible y peajes." },
    { title: "Mantén el vehículo", body: "Un mantenimiento oportuno evita reparaciones costosas." }
  ],
  "Taxis y apps" => [
    { title: "Combina trayectos", body: "Agrupa varios destinos en un solo viaje." },
    { title: "Usa transporte público", body: "Para trayectos cortos considera opciones más económicas." }
  ],
  "Cuidado personal" => [
    { title: "Espacia las citas", body: "Extiende un poco el tiempo entre citas no esenciales." },
    { title: "Busca promociones", body: "Aprovecha descuentos en peluquería o gimnasio." }
  ],
  "Ocio y salidas" => [
    { title: "Planifica salidas", body: "Define un presupuesto para entretenimiento cada ciclo." },
    { title: "Busca actividades gratuitas", body: "Aprovecha eventos y actividades sin costo." }
  ],
  "Suscripciones" => [
    { title: "Cancela las no usadas", body: "Revisa qué suscripciones realmente utilizas." },
    { title: "Comparte planes familiares", body: "Los planes compartidos reducen el costo por persona." }
  ],
  "Gustos y compras" => [
    { title: "Espera 24 horas", body: "Antes de una compra impulsiva, espera un día para decidir." },
    { title: "Haz una lista de deseos", body: "Prioriza compras importantes y evita gastos innecesarios." }
  ],
  "Viajes" => [
    { title: "Reserva con anticipación", body: "Los tiquetes y hoteles suelen ser más baratos con tiempo." },
    { title: "Compara fechas", body: "Viajar en temporada baja reduce costos." }
  ],
  "Seguros" => [
    { title: "Compara pólizas", body: "Revisa si existe una cobertura equivalente a menor costo." },
    { title: "Ajusta las coberturas", body: "Evita pagar por coberturas que no necesitas." }
  ],
  "Donaciones y regalos" => [
    { title: "Define un monto mensual", body: "Asigna un tope para regalos y donaciones." },
    { title: "Busca regalos significativos", body: "Un regalo bien pensado puede ser económico." }
  ]
}.freeze

CATEGORY_SAVING_TIPS.each do |name, tips|
  category = Category.find_by(name: name, is_default: true, category_type: "expense")
  next unless category

  tips.each_with_index do |tip_attrs, index|
    SubcategorySavingTip.find_or_create_by!(subcategory: category, title: tip_attrs[:title]) do |tip|
      tip.body = tip_attrs[:body]
      tip.active = true
      tip.position = index
    end
  end
end
