# frozen_string_literal: true

require_relative "legal_document_helpers"

# Initial content for the Maglev terms and conditions page. This is a
# preliminary operational draft: unverified legal data is explicitly marked.
module TermsAndConditionsSeed
  extend LegalDocumentHelpers

  PAGE = {
    title: "Términos y condiciones",
    path: "terminos-y-condiciones",
    seo_title: "Términos y condiciones",
    meta_description: "Conoce las condiciones de uso de Yogasto, las reglas de nuestras membresías y tus derechos y responsabilidades al utilizar la plataforma.",
    og_title: "Términos y condiciones",
    og_description: "Reglas claras para usar Yogasto y entender tus derechos y responsabilidades.",
    meta_robots: "noindex,follow"
  }.freeze

  DOCUMENT_SETTINGS = {
    eyebrow: "INFORMACIÓN LEGAL",
    title: "Reglas claras para una mejor experiencia.",
    description: "Estos términos explican las condiciones para usar Yogasto, tus responsabilidades y los compromisos que asumimos para ofrecerte nuestro servicio.",
    last_updated: "6 de noviembre de 2026",
    reading_time: "9 minutos",
    reading_label: "Lectura aproximada: ",
    updated_label: "Última actualización: ",
    meta_order: "reading_first",
    breadcrumb_parent_label: "Información legal",
    breadcrumb_parent_url: "",
    breadcrumb_current_label: "Términos y condiciones",
    toc_label: "EN ESTA PÁGINA",
    help_title: "¿Tienes alguna pregunta?",
    help_text: "Estamos aquí para ayudarte.",
    help_link: { link_type: "url", href: "/contactanos", text: "Contactar con soporte", open_new_window: false },
    intro: "Te recomendamos leer estos términos antes de crear una cuenta o utilizar las funcionalidades de Yogasto. Al registrarte, acceder o utilizar la plataforma, confirmas que has leído y aceptas estas condiciones.",
    notice_title: "Un punto importante",
    notice_text: "Yogasto es una herramienta para organizar y comprender tus finanzas personales. No es una entidad financiera, no custodia tu dinero ni reemplaza el criterio de un profesional financiero, contable o tributario.",
    review_title: "Versión preliminar en revisión legal",
    review_text: "Estamos completando los datos del titular, las condiciones definitivas de membresías y pagos y la información de contacto legal. No consideres esta versión como definitiva.",
    cta_title: "¿Necesitas que te ayudemos?",
    cta_text: "Estamos aquí para resolver tus dudas sobre el uso de Yogasto.",
    cta_link: { link_type: "url", href: "/ayuda", text: "Visitar centro de ayuda", open_new_window: false }
  }.freeze

  SECTIONS = [
    section(
      anchor: "aceptacion",
      number: "01",
      title: "Aceptación de los términos",
      nav_label: "Aceptación de los términos",
      children: [
        text("<p>Estos Términos y condiciones regulan el acceso y uso de Yogasto, incluyendo su sitio web, aplicación, funcionalidades, integraciones y servicios relacionados.</p>"),
        text("<p>Si no estás de acuerdo con alguna de estas condiciones, debes abstenerte de utilizar el servicio. Si utilizas Yogasto en nombre de otra persona o entidad, declaras que tienes autorización para aceptar estos términos en su nombre.</p>"),
        callout("Aceptación", "El registro, acceso o uso de la plataforma implica la aceptación de las condiciones aplicables y de la Política de privacidad.", "note")
      ]
    ),
    section(
      anchor: "servicio",
      number: "02",
      title: "Sobre Yogasto",
      nav_label: "Sobre Yogasto",
      children: [
        text("<p>Yogasto es una plataforma digital que te permite registrar, organizar y consultar información relacionada con tus finanzas personales.</p>"),
        list([
          "Gastos e ingresos.",
          "Cuentas y medios de dinero.",
          "Deudas y obligaciones.",
          "Presupuestos, metas y transferencias.",
          "Reportes, análisis y herramientas inteligentes."
        ]),
        text("<p>Las funcionalidades disponibles pueden variar según el plan contratado, la configuración de tu cuenta y las actualizaciones del servicio.</p>"),
        callout("Yogasto no es una entidad financiera", "Yogasto no custodia dinero, no ejecuta operaciones bancarias y no presta asesoría financiera, de inversión, contable ni tributaria. La información y los resultados que presenta son herramientas de organización y análisis.", "warning")
      ]
    ),
    section(
      anchor: "cuenta",
      number: "03",
      title: "Tu cuenta",
      nav_label: "Tu cuenta",
      children: [
        text("<p>Para utilizar determinadas funcionalidades necesitas crear una cuenta y proporcionar información correcta y actualizada.</p>"),
        list([
          "Eres responsable de mantener la confidencialidad de tus credenciales.",
          "Debes notificarnos si sospechas que alguien accedió a tu cuenta sin autorización.",
          "No debes compartir, vender ni transferir tu cuenta a otra persona.",
          "Debes tener capacidad legal para aceptar estos términos y cumplir los requisitos de edad aplicables."
        ]),
        callout("Requisitos de edad pendientes", "La edad mínima y el mecanismo de verificación o autorización de menores deben definirse y validarse legalmente antes de publicar esta versión.", "warning")
      ]
    ),
    section(
      anchor: "uso",
      number: "04",
      title: "Uso permitido de la plataforma",
      nav_label: "Uso permitido",
      children: [
        text("<p>Te comprometes a utilizar Yogasto de manera legal, responsable y de acuerdo con estos términos. No está permitido:</p>"),
        list([
          "Utilizar el servicio para actividades fraudulentas, ilegales o que vulneren derechos de terceros.",
          "Intentar acceder sin autorización a cuentas, sistemas o información de otros usuarios.",
          "Interferir con el funcionamiento, seguridad o disponibilidad de la plataforma.",
          "Realizar ingeniería inversa no autorizada, extraer masivamente datos o explotar vulnerabilidades.",
          "Introducir código malicioso o utilizar el servicio para enviar comunicaciones no solicitadas."
        ])
      ]
    ),
    section(
      anchor: "datos",
      number: "05",
      title: "Tu información financiera",
      nav_label: "Tu información financiera",
      children: [
        text("<p>La información que registras en Yogasto sigue siendo tuya. Nos autorizas a tratarla en la medida necesaria para prestar, mantener, proteger y mejorar las funcionalidades que utilizas, de acuerdo con nuestra <a href='/privacidad'>Política de privacidad</a>.</p>"),
        cards([
          card(icon: "◎", title: "Tus registros", text: "Procura que los datos que ingresas sean correctos y mantén tus registros actualizados."),
          card(icon: "✓", title: "Tu responsabilidad", text: "Verifica importes, fechas, categorías, cuentas y resultados antes de tomar decisiones.")
        ]),
        text("<p>Yogasto no verifica de forma independiente que cada movimiento registrado corresponda a una operación real. Las importaciones y automatizaciones pueden requerir revisión o corrección por tu parte.</p>")
      ]
    ),
    section(
      anchor: "ia",
      number: "06",
      title: "Herramientas e inteligencia artificial",
      nav_label: "Herramientas e IA",
      children: [
        text("<p>Algunas funcionalidades pueden utilizar automatización o inteligencia artificial para interpretar textos, clasificar movimientos, generar resúmenes o ayudarte a consultar tu información.</p>"),
        list([
          "Los resultados automáticos pueden contener errores, omisiones o interpretaciones incorrectas.",
          "Debes revisar los datos sugeridos antes de confirmarlos o utilizarlos.",
          "No debes considerar las respuestas generadas como recomendaciones profesionales o garantías de resultados.",
          "El uso de proveedores tecnológicos externos se describe en la Política de privacidad."
        ]),
        callout("Las herramientas inteligentes son de apoyo", "Tú conservas el control sobre los registros y decisiones que realizas en Yogasto. Si no deseas usar una función inteligente, puedes utilizar las funciones manuales disponibles.", "note")
      ]
    ),
    section(
      anchor: "planes",
      number: "07",
      title: "Planes y membresías",
      nav_label: "Planes y membresías",
      children: [
        text("<p>Yogasto puede ofrecer un plan gratuito, periodos de prueba y planes de pago con diferentes funcionalidades, límites y condiciones.</p>"),
        list([
          "El plan Gratis se ofrece según las reglas vigentes y puede estar limitado a quienes no han tenido una membresía.",
          "La prueba gratuita solo puede utilizarse una vez por cuenta y tiene la duración informada en la aplicación.",
          "Los planes de pago tienen la duración y el precio informados antes de la compra.",
          "La renovación no es automática por defecto: el usuario debe realizar un nuevo pago cuando termine el periodo, salvo que se informe expresamente lo contrario.",
          "Si compras un nuevo periodo mientras tu membresía está vigente, el tiempo se suma al periodo actual según las reglas del sistema.",
          "Al finalizar la membresía, las funciones Pro dejan de estar disponibles y la cuenta permanece sujeta a las condiciones del plan aplicable."
        ]),
        callout("Condiciones pendientes de confirmar", "Deben validarse las reglas definitivas de vencimiento, acceso posterior a la información y disponibilidad del plan Gratis para cada tipo de cuenta antes de publicar esta versión.", "warning")
      ]
    ),
    section(
      anchor: "pagos",
      number: "08",
      title: "Pagos y facturación",
      nav_label: "Pagos y facturación",
      children: [
        text("<p>Los planes de pago se abonan mediante los medios disponibles al momento de la compra. El procesamiento puede estar a cargo de proveedores externos, como ePayco, cuyas condiciones también pueden aplicar a la transacción.</p>"),
        list([
          "Los medios de pago habilitados se muestran en el checkout. La implementación actual permite tarjeta y PSE.",
          "El precio y la moneda aplicables se muestran antes de confirmar el pago.",
          "La activación del plan está sujeta a la confirmación del pago por parte del proveedor.",
          "Un pago pendiente, rechazado o fallido no activa la membresía.",
          "Si la activación presenta un error, puedes contactar a soporte con los datos de la transacción.",
          "No se presupone una renovación automática; el usuario debe adquirir un nuevo periodo cuando corresponda."
        ]),
        callout("Reembolsos y facturación pendientes", "Las condiciones definitivas de reembolso, reversión, facturación y atención de disputas deben definirse con revisión legal y publicarse antes de considerar esta sección definitiva. No se inventan plazos ni garantías.", "warning")
      ]
    ),
    section(
      anchor: "disponibilidad",
      number: "09",
      title: "Disponibilidad y cambios del servicio",
      nav_label: "Disponibilidad del servicio",
      children: [
        text("<p>Trabajamos para mantener Yogasto disponible y seguro, pero no podemos garantizar que el servicio esté libre de interrupciones, errores o periodos de mantenimiento.</p>"),
        text("<p>Podemos actualizar, modificar o retirar funcionalidades por razones técnicas, operativas, de seguridad o de evolución del producto. Cuando un cambio afecte de manera significativa una funcionalidad contratada, procuraremos comunicarlo por los medios disponibles y conforme a la normativa aplicable.</p>")
      ]
    ),
    section(
      anchor: "propiedad",
      number: "10",
      title: "Propiedad intelectual",
      nav_label: "Propiedad intelectual",
      children: [
        text("<p>Yogasto, su marca, diseño, software, textos, elementos gráficos y demás componentes están protegidos por las normas de propiedad intelectual que resulten aplicables.</p>"),
        text("<p>Tu acceso al servicio te concede una autorización limitada, personal, no exclusiva y no transferible para utilizar la plataforma conforme a estos términos. No adquieres derechos de propiedad sobre el software ni sobre sus componentes.</p>"),
        callout("Titularidad pendiente", "La identificación del titular legal de la marca y del software debe confirmarse antes de publicar esta sección.", "warning")
      ]
    ),
    section(
      anchor: "responsabilidad",
      number: "11",
      title: "Responsabilidad y limitaciones",
      nav_label: "Responsabilidad",
      children: [
        text("<p>En la medida permitida por la ley, Yogasto no será responsable por decisiones que tomes basándote exclusivamente en información registrada, cálculos, clasificaciones o resultados automáticos de la plataforma.</p>"),
        text("<p>Tampoco podemos garantizar la exactitud de información obtenida de servicios externos o de datos que hayas ingresado incorrectamente. Nada de lo dispuesto en estos términos pretende excluir derechos o responsabilidades que legalmente no puedan excluirse o limitarse, incluidos los derechos irrenunciables del consumidor.</p>")
      ]
    ),
    section(
      anchor: "terminacion",
      number: "12",
      title: "Suspensión y terminación",
      nav_label: "Suspensión y terminación",
      children: [
        text("<p>Puedes dejar de utilizar Yogasto y solicitar la eliminación de tu cuenta desde tu perfil o contactando a soporte. La eliminación de la cuenta es permanente y elimina el acceso y los registros asociados según la <a href='/privacidad'>Política de privacidad</a>.</p>"),
        text("<p>Podemos suspender o limitar el acceso cuando existan indicios razonables de fraude, uso abusivo, riesgos de seguridad, incumplimiento de estos términos o una obligación legal que así lo requiera. Cuando sea posible y apropiado, te informaremos el motivo y los pasos para resolver la situación.</p>"),
        callout("Respaldos pendientes", "No se promete eliminación inmediata de copias de respaldo. Los plazos de retención de respaldos deben confirmarse antes de publicar esta sección.", "warning")
      ]
    ),
    section(
      anchor: "cambios",
      number: "13",
      title: "Cambios en estos términos",
      nav_label: "Cambios en los términos",
      children: [
        text("<p>Podemos actualizar estos términos para reflejar cambios en Yogasto, en la legislación o en nuestras prácticas. Publicaremos la versión vigente en esta página e indicaremos su fecha de actualización.</p>"),
        text("<p>Cuando los cambios sean materiales, procuraremos informarte por un medio adecuado. El uso continuado del servicio después de la entrada en vigor de los cambios estará sujeto a las condiciones actualizadas, sin perjuicio de los derechos que te reconozca la ley.</p>")
      ]
    ),
    section(
      anchor: "ley",
      number: "14",
      title: "Ley aplicable y contacto",
      nav_label: "Ley aplicable y contacto",
      children: [
        text("<p>Estos términos se interpretarán conforme a las leyes aplicables de la República de Colombia, sin perjuicio de las normas imperativas de protección al consumidor que correspondan.</p>"),
        text("<p>Si tienes preguntas, solicitudes o reclamos relacionados con estos términos, puedes comunicarte con nosotros a través de <a href='/contactanos'>Contáctanos</a>.</p>"),
        callout("Información pendiente de completar", "Antes de publicar deben confirmarse la razón social o titular responsable, identificación legal, domicilio, correo oficial, reglas definitivas de membresías y pagos, reembolsos, jurisdicción y mecanismos de atención de reclamaciones.", "warning")
      ]
    )
  ].freeze
end
