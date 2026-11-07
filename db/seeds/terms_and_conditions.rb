# frozen_string_literal: true

require_relative "legal_document_helpers"

# Public content for the Maglev terms and conditions page. Only verified,
# user-facing statements belong here. Internal legal checks and pending
# decisions live in docs/terms_and_conditions_audit.md.
module TermsAndConditionsSeed
  extend LegalDocumentHelpers

  PAGE = {
    title: "Términos y condiciones",
    path: "terminos-y-condiciones",
    seo_title: "Términos y condiciones",
    meta_description: "Conoce las condiciones de uso de Yogasto, las reglas de nuestros planes y tus derechos y responsabilidades al utilizar la plataforma.",
    og_title: "Términos y condiciones",
    og_description: "Reglas claras para usar Yogasto y entender tus derechos y responsabilidades.",
    meta_robots: "index,follow"
  }.freeze

  DOCUMENT_SETTINGS = {
    eyebrow: "INFORMACIÓN LEGAL",
    title: "Reglas claras para una mejor experiencia.",
    description: "Estos términos explican las condiciones para usar Yogasto, tus responsabilidades y los compromisos que asumimos para ofrecerte nuestro servicio.",
    last_updated: "7 de noviembre de 2026",
    reading_time: "12 minutos",
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
    review_title: "",
    review_text: "",
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
        text("<p>Estos términos regulan el acceso y uso de Yogasto, incluyendo el sitio web https://yogasto.co, la aplicación, sus funcionalidades, integraciones y servicios relacionados.</p>"),
        text("<p>Al crear una cuenta, acceder o utilizar la plataforma aceptas estos términos y nuestra <a href='/privacidad'>Política de privacidad</a>. Si no estás de acuerdo, debes abstenerte de utilizar el servicio.</p>"),
        text("<p>Si utilizas Yogasto en nombre de otra persona o entidad, declaras que tienes autorización para aceptar estas condiciones en su nombre.</p>")
      ]
    ),
    section(
      anchor: "servicio",
      number: "02",
      title: "Identificación del servicio",
      nav_label: "Identificación del servicio",
      children: [
        text("<p>Yogasto es una aplicación de finanzas personales que permite registrar, organizar, consultar y analizar ingresos, gastos, cuentas, fuentes de dinero, deudas, transferencias y otros movimientos financieros personales.</p>"),
        text("<p>La plataforma también ofrece funcionalidades de automatización, importación de información y procesamiento mediante inteligencia artificial.</p>"),
        text("<p>Yogasto es operado por José Uribe, persona natural, con domicilio en Soledad, Atlántico, Colombia. El canal de contacto y atención de solicitudes es <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>.</p>"),
        callout("Yogasto no es una entidad financiera", "Yogasto no custodia dinero, no ejecuta operaciones bancarias y no presta asesoría financiera, de inversión, contable ni tributaria. La información y los resultados que presenta son herramientas de organización y análisis.", "warning")
      ]
    ),
    section(
      anchor: "registro",
      number: "03",
      title: "Edad mínima y registro",
      nav_label: "Edad mínima y registro",
      children: [
        text("<p>Solo pueden crear una cuenta personas mayores de 18 años. Al registrarte declaras que cumples esta condición.</p>"),
        list([
          "Cada usuario es responsable de la información que registra y de mantener la confidencialidad de sus credenciales y métodos de autenticación.",
          "La cuenta es personal y no debe compartirse, venderse ni transferirse a terceros.",
          "Debes proporcionar información veraz y mantenerla actualizada.",
          "Si sospechas que alguien accedió a tu cuenta sin autorización, debes notificarlo a Yogasto y cambiar tus credenciales."
        ])
      ]
    ),
    section(
      anchor: "planes",
      number: "04",
      title: "Planes y funcionalidades",
      nav_label: "Planes y funcionalidades",
      intro: "Yogasto tiene dos modalidades de acceso: Gratis y Pro.",
      children: [
        text("<p><strong>Plan Gratis.</strong> Es un plan permanente que permite gestionar tus finanzas personales mediante las funcionalidades básicas de la plataforma. Incluye, entre otras:</p>"),
        list([
          "Registro manual de gastos e ingresos.",
          "Gestión de cuentas y fuentes de dinero.",
          "Gestión de categorías.",
          "Registro de movimientos y transferencias.",
          "Gestión de deudas.",
          "Consulta y organización de la información financiera.",
          "Las demás funcionalidades básicas que no estén reservadas expresamente para Pro."
        ]),
        text("<p><strong>Plan Pro.</strong> Incluye todas las funcionalidades del plan Gratis y, adicionalmente:</p>"),
        cards([
          card(icon: "▤", title: "Importación y procesamiento", text: "Carga y procesamiento de extractos bancarios."),
          card(icon: "⇄", title: "Automatizaciones", text: "Automatizaciones mediante correo electrónico y Gmail, integraciones y procesamiento mediante WhatsApp, integración mediante MCP y asistentes de inteligencia artificial, reglas, automatizaciones y gestión de candidatos de movimientos."),
          card(icon: "✦", title: "Inteligencia artificial", text: "Chat financiero, análisis de hábitos financieros, identificación de oportunidades de ahorro, análisis de ahorro por categoría y otras herramientas de inteligencia artificial disponibles en Pro.")
        ]),
        text("<p>La disponibilidad de funcionalidades puede depender del plan contratado y de las condiciones técnicas de cada integración.</p>")
      ]
    ),
    section(
      anchor: "prueba",
      number: "05",
      title: "Periodo de prueba",
      nav_label: "Periodo de prueba",
      children: [
        text("<p>Yogasto ofrece un periodo de prueba de sesenta (60) días, disponible una vez por cuenta.</p>"),
        list([
          "El periodo de prueba no requiere registrar una tarjeta de crédito o débito.",
          "El periodo de prueba no genera cobros automáticos.",
          "Durante el periodo de prueba puedes acceder a las funcionalidades Pro.",
          "Al finalizar el periodo de prueba, la cuenta pasa automáticamente al plan Gratis, salvo que contrates Pro.",
          "No se realiza ningún cobro por el simple vencimiento del periodo de prueba."
        ])
      ]
    ),
    section(
      anchor: "pagos",
      number: "06",
      title: "Precios y pagos",
      nav_label: "Precios y pagos",
      intro: "Los precios definidos actualmente son:",
      children: [
        list([
          "<strong>Plan mensual:</strong> $14.900 COP por un periodo de un mes.",
          "<strong>Plan anual:</strong> $149.900 COP por un periodo de doce meses."
        ]),
        text("<p>Los pagos son individuales y deben ser iniciados manualmente por el usuario. No existe renovación automática.</p>"),
        list([
          "Al finalizar el periodo contratado, el acceso Pro vence si el usuario no realiza un nuevo pago.",
          "El usuario puede contratar nuevamente Pro cuando lo desee.",
          "Si compras un nuevo periodo mientras tu acceso Pro está vigente, el tiempo se suma al periodo actual.",
          "Los pagos se procesan mediante los medios de pago habilitados en el proceso de compra. Actualmente el checkout permite tarjeta y PSE.",
          "La activación del plan está sujeta a la confirmación del pago por parte del proveedor. Un pago pendiente, rechazado o fallido no activa la membresía.",
          "Yogasto puede actualizar sus precios en el futuro. Cualquier cambio se informará de forma clara y no modificará retroactivamente periodos ya pagados."
        ]),
        text("<p>El procesamiento de pagos puede estar a cargo de proveedores externos, como ePayco, cuyas condiciones también pueden aplicar a la transacción. Si tienes un problema con un pago, escribe a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a> con los datos de la transacción.</p>")
      ]
    ),
    section(
      anchor: "vencimiento",
      number: "07",
      title: "Vencimiento del plan Pro",
      nav_label: "Vencimiento del plan Pro",
      intro: "Cuando termina el periodo de prueba o vence un periodo Pro:",
      children: [
        list([
          "La cuenta pasa al plan Gratis.",
          "Las funcionalidades exclusivas de Pro dejan de estar disponibles.",
          "La información financiera del usuario se conserva.",
          "El usuario mantiene acceso a las funcionalidades del plan Gratis.",
          "El usuario puede volver a contratar Pro en cualquier momento."
        ]),
        text("<p>El vencimiento de Pro no implica la eliminación de la cuenta ni de la información registrada.</p>")
      ]
    ),
    section(
      anchor: "cierre",
      number: "08",
      title: "Cancelación y cierre de cuenta",
      nav_label: "Cierre de cuenta",
      intro: "Puedes cerrar tu cuenta desde la sección Perfil, mediante la opción de cierre de cuenta disponible allí. Esta opción está disponible en cualquier momento.",
      children: [
        text("<p>Al cerrar la cuenta:</p>"),
        list([
          "Se elimina la cuenta principal del usuario.",
          "Se eliminan los datos y registros asociados a ella, incluyendo movimientos, ingresos, gastos, cuentas, fuentes de dinero, categorías, deudas y demás información vinculada.",
          "La operación debe considerarse definitiva para el usuario.",
          "El cierre no está condicionado a la contratación de un plan, a la finalización de un periodo Pro ni a contactar previamente con soporte."
        ]),
        text("<p>Yogasto respetará las obligaciones legales de conservación de información que puedan aplicar. Las copias de seguridad pueden seguir ciclos técnicos de eliminación y no necesariamente desaparecen de forma instantánea.</p>"),
        text("<p>El cierre de cuenta no genera automáticamente un reembolso proporcional por el tiempo restante de un periodo contratado, sin perjuicio de los derechos legales del consumidor.</p>")
      ]
    ),
    section(
      anchor: "retracto",
      number: "09",
      title: "Retracto, devoluciones y reversión de pagos",
      nav_label: "Retracto y devoluciones",
      children: [
        text("<p>Yogasto respeta los derechos del consumidor reconocidos por la legislación colombiana, incluyendo la Ley 1480 de 2011. Nada en estos términos pretende limitar derechos irrenunciables.</p>"),
        text("<p><strong>Derecho de retracto.</strong> En las ventas a distancia o electrónicas, el consumidor puede ejercer el derecho de retracto conforme a las condiciones, excepciones y plazos establecidos en la legislación colombiana, incluyendo el artículo 47 de la Ley 1480 de 2011.</p>"),
        text("<p><strong>Reversión de pagos.</strong> La reversión del pago se rige por las condiciones legales aplicables, incluyendo los supuestos previstos en el artículo 51 de la Ley 1480 de 2011. Cuando proceda, la solicitud se tramitará por los canales del proveedor de pagos y conforme a la ley.</p>"),
        text("<p><strong>Devoluciones por incumplimiento o prestación defectuosa.</strong> Si consideras que el servicio no se prestó correctamente o presenta una falla, puedes presentar una solicitud para que sea revisada. Yogasto atenderá la solicitud conforme a sus obligaciones legales y a los derechos que te correspondan.</p>"),
        text("<p><strong>Simple arrepentimiento después de utilizar el servicio.</strong> Una solicitud de devolución por simple arrepentimiento una vez utilizado el servicio no es lo mismo que el derecho de retracto. Su procedencia se evaluará conforme a la ley y a las excepciones aplicables. No se promete un reembolso automático por cancelar la cuenta o dejar de utilizar el servicio.</p>"),
        text("<p>Cuando el checkout solicite una aceptación expresa e independiente para el inicio inmediato de la prestación del servicio, esa aceptación no constituirá una renuncia general a los derechos del consumidor ni eliminará automáticamente el derecho de retracto. La procedencia de cualquier excepción legal se evaluará conforme a sus requisitos y a la ley aplicable.</p>"),
        text("<p>Para presentar una solicitud de retracto, reversión o devolución, escribe a <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a> con el correo asociado a tu cuenta, la referencia del pago, el motivo de la solicitud y la información que permita identificarla. La solicitud se atenderá dentro de los plazos legales aplicables.</p>")
      ]
    ),
    section(
      anchor: "ia",
      number: "10",
      title: "Uso de inteligencia artificial y automatizaciones",
      nav_label: "Inteligencia artificial",
      children: [
        text("<p>Yogasto ofrece funcionalidades que utilizan inteligencia artificial y automatización para procesar, clasificar, interpretar y analizar información financiera.</p>"),
        list([
          "Los resultados generados por inteligencia artificial pueden contener errores o imprecisiones.",
          "Las sugerencias y análisis son orientativos y se basan en la información disponible.",
          "Debes revisar los movimientos, importes, categorías y resultados antes de utilizarlos como referencia para tomar decisiones.",
          "Las recomendaciones no constituyen asesoría financiera, contable, tributaria ni de inversión personalizada.",
          "Eres responsable de verificar la información financiera registrada en tu cuenta."
        ]),
        text("<p>No prometemos que la inteligencia artificial identifique correctamente todos los movimientos. Si no deseas utilizar una función inteligente, puedes continuar utilizando las funciones manuales disponibles. El tratamiento de datos por proveedores de inteligencia artificial se describe en la <a href='/privacidad'>Política de privacidad</a>.</p>")
      ]
    ),
    section(
      anchor: "terceros",
      number: "11",
      title: "Integraciones y servicios de terceros",
      nav_label: "Servicios de terceros",
      children: [
        text("<p>Yogasto puede ofrecer integraciones con servicios externos, proveedores de correo electrónico, plataformas de mensajería, servicios de pago y herramientas de inteligencia artificial.</p>"),
        list([
          "El funcionamiento de estas integraciones puede depender de la disponibilidad y condiciones de terceros.",
          "Los servicios externos pueden modificar sus condiciones, APIs, permisos o disponibilidad.",
          "Yogasto no controla las interrupciones o modificaciones que sean responsabilidad exclusiva de esos proveedores.",
          "El usuario debe autorizar las conexiones y permisos que decida utilizar."
        ]),
        text("<p>Los proveedores tecnológicos utilizados actualmente se describen en la <a href='/privacidad'>Política de privacidad</a>. Esa información puede actualizarse cuando cambien las integraciones disponibles.</p>")
      ]
    ),
    section(
      anchor: "responsabilidades",
      number: "12",
      title: "Responsabilidades del usuario",
      nav_label: "Responsabilidades del usuario",
      intro: "El usuario se compromete a:",
      children: [
        list([
          "Utilizar Yogasto de manera legal y adecuada.",
          "No intentar acceder a cuentas o información de otros usuarios.",
          "No interferir con la seguridad o el funcionamiento de la plataforma.",
          "No utilizar la aplicación para actividades fraudulentas o ilícitas.",
          "Proporcionar información correcta y revisar los datos procesados automáticamente.",
          "Mantener protegidos sus métodos de acceso.",
          "No realizar ingeniería inversa, explotación de vulnerabilidades o uso abusivo de la plataforma."
        ]),
        text("<p>Yogasto puede suspender o limitar el acceso cuando existan indicios razonables de fraude, uso abusivo, riesgos de seguridad, incumplimiento de estos términos o una obligación legal que así lo requiera. Cuando sea posible y apropiado, se informará el motivo y los pasos para resolver la situación.</p>")
      ]
    ),
    section(
      anchor: "disponibilidad",
      number: "13",
      title: "Disponibilidad y modificaciones del servicio",
      nav_label: "Disponibilidad del servicio",
      children: [
        text("<p>Yogasto realizará esfuerzos razonables para mantener la disponibilidad de la plataforma. Sin embargo, pueden presentarse interrupciones por mantenimiento, actualizaciones, fallos técnicos, problemas de conectividad o situaciones externas.</p>"),
        text("<p>Yogasto puede modificar, mejorar, sustituir o retirar funcionalidades, informando cuando corresponda y respetando las obligaciones legales y los periodos contratados.</p>"),
        text("<p>Ninguna disposición de estos términos pretende excluir derechos o responsabilidades que legalmente no puedan excluirse o limitarse, incluidos los derechos irrenunciables del consumidor.</p>")
      ]
    ),
    section(
      anchor: "propiedad",
      number: "14",
      title: "Propiedad intelectual",
      nav_label: "Propiedad intelectual",
      children: [
        text("<p>Yogasto, su marca, diseño, software, textos, elementos gráficos y demás componentes están protegidos por las normas de propiedad intelectual que resulten aplicables.</p>"),
        text("<p>El uso de la plataforma te concede una autorización limitada, personal, no exclusiva y no transferible para utilizar el servicio conforme a estos términos. No adquieres derechos de propiedad sobre el software ni sobre sus componentes.</p>"),
        text("<p>El usuario conserva los derechos que le correspondan sobre su propia información y los datos que registra en Yogasto. El uso de la plataforma no transfiere al usuario derechos de propiedad intelectual sobre el software o sus componentes.</p>")
      ]
    ),
    section(
      anchor: "privacidad",
      number: "15",
      title: "Privacidad y tratamiento de datos",
      nav_label: "Privacidad y datos",
      children: [
        text("<p>El tratamiento de datos personales se rige por la <a href='/privacidad'>Política de privacidad</a> de Yogasto y por la legislación colombiana aplicable, incluyendo la Ley 1581 de 2012 y sus normas reglamentarias.</p>"),
        text("<p>Estos términos no sustituyen la autorización o la información que legalmente corresponda para el tratamiento de datos personales. Las autorizaciones para comunicaciones comerciales se mantienen separadas y son opcionales; puedes gestionarlas desde tu perfil.</p>")
      ]
    ),
    section(
      anchor: "cambios",
      number: "16",
      title: "Cambios en estos términos",
      nav_label: "Cambios en los términos",
      children: [
        text("<p>Yogasto puede actualizar estos términos para reflejar cambios en el servicio, en la legislación o en sus prácticas. La versión vigente se publicará en esta página con su fecha de actualización.</p>"),
        text("<p>Cuando los cambios sean materiales, se procurará informar por un medio adecuado. El uso continuado del servicio después de la entrada en vigor de los cambios estará sujeto a las condiciones actualizadas, sin perjuicio de los derechos que reconozca la ley. Si no estás de acuerdo con los cambios, puedes cerrar tu cuenta.</p>")
      ]
    ),
    section(
      anchor: "contacto",
      number: "17",
      title: "Reclamaciones y contacto",
      nav_label: "Reclamaciones y contacto",
      intro: "Puedes presentar solicitudes, consultas, quejas o reclamaciones mediante:",
      children: [
        list([
          "El formulario de contacto de Yogasto.",
          "El correo <a href='mailto:hola@yogasto.co'>hola@yogasto.co</a>."
        ]),
        text("<p>Incluye el correo asociado a tu cuenta, el motivo de tu solicitud y la información necesaria para identificarla. Las solicitudes se atenderán conforme a los procedimientos y plazos legales aplicables, sin perjuicio de que puedas acudir a las autoridades competentes.</p>"),
        text("<p>Para solicitudes relacionadas con datos personales, consulta el canal indicado en la <a href='/privacidad'>Política de privacidad</a>.</p>")
      ]
    ),
    section(
      anchor: "ley",
      number: "18",
      title: "Legislación aplicable",
      nav_label: "Legislación aplicable",
      children: [
        text("<p>Estos términos se interpretarán conforme a las leyes de la República de Colombia, respetando las normas imperativas de protección al consumidor y protección de datos personales que resulten aplicables.</p>"),
        text("<p>Ninguna disposición de estos términos obliga al consumidor a renunciar a derechos o a mecanismos legales de reclamación. Cualquier controversia se resolverá conforme a la ley colombiana y ante las autoridades competentes.</p>")
      ]
    )
  ].freeze
end
