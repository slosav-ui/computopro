# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Idioma de respuesta

Responder siempre en español al trabajar en este repositorio, sin importar el idioma de este documento.

## Reglas de edición

1. Nunca modificar código que no esté directamente relacionado con lo que se pidió explícitamente.
2. Si una tarea requiere tocar más archivos de los esperados, preguntar antes de proceder.
3. Preferir agregar código nuevo (nuevas funciones, nuevos widgets) en vez de reescribir funciones existentes, salvo que se pida explícitamente una modificación.
4. Antes de cualquier cambio, explicar en una línea qué se va a tocar y por qué.
5. Nunca eliminar código existente sin que se solicite explícitamente.

## Project

Flutter app (`mi_primera_app` in `pubspec.yaml`) for managing construction projects ("obras") and their budgets ("presupuestos") in the Argentine construction market. UI, domain terms, and comments are in Spanish (rioplatense/Argentine): APU = Análisis de Precios Unitarios (unit price analysis), CAC = índice de la Cámara Argentina de la Construcción (cost adjustment index), IRAM = Argentine technical standards body, UOCRA = construction workers' union (referenced for cargas sociales / payroll charges).

## Especificación funcional y de negocio (resumen de `docs/especificacion_funcional*.md`)

Fuentes: `especificacion_funcional.md`, `_2.md` y `_3.md` (transcripciones de conversaciones de diseño con el usuario, se repiten bastante entre sí) más `especificacion_funcional_completa.md` y `_parte2_fundacional.md` (spec histórica extraída de meses de trabajo previo con Gemini, anterior a la migración a Claude Code — no specs formales tampoco). Esto es la referencia funcional/de producto permanente del proyecto — el código actual todavía no implementa la mayoría de estos puntos, son el objetivo a futuro.

### Origen del proyecto: por qué existen las "Reglas de edición"

El proyecto se migró desde meses de trabajo con Gemini. El propio Gemini diagnosticó la causa raíz del problema que motivó la migración: *"El desvío ocurrió cuando comenzamos a tocar y modificar en bloque los códigos de la interfaz sin seguir el método quirúrgico archivo por archivo... el código monolítico empezó a sobreescribirse, rompiendo la modularidad."* — funcionalidades enteras se perdían en reescrituras masivas. La sección "Reglas de edición" de este archivo (trabajo quirúrgico, archivo por archivo, sin tocar lo que no se pidió) es la respuesta directa a esa experiencia, no una preferencia arbitraria.

Nota positiva verificada: la lista histórica de funcionalidades de `obras_list_screen.dart` que se habían perdido en una reescritura y debían recuperarse (banda de cotización USD BNA compra/venta, proyección personalizada PRO con reseteo, mapa de obras interactivo, alta de obra con selectores de tipo/moneda, modal de Servicios Especiales con checklist y adjuntar planos, modal Plan PRO con desglose de beneficios, Ajuste Económico & Moneda con toggle CAC) **ya está recuperada y presente en el código actual** — no es una brecha pendiente.

### Posicionamiento y modelo de negocio

ComputoPRO es una herramienta **B2B / de nicho profesional**, no una app masiva de consumo. Target: arquitectos, maestros mayores de obra, constructores independientes y estudios chicos que manejan entre 2 y 10 obras simultáneas en Argentina. Monetización: suscripción SaaS mensual/anual (no publicidad, no venta única). Regla de proceso acordada explícitamente con el usuario: **evitar scope creep** — priorizar el MVP (cómputo, APU, materiales, resumen de obra) y dejar ideas futuras en un backlog, sin desviarse del nicho ni intentar ser una app para "cualquier usuario". Antes de escribir código para una funcionalidad nueva de negocio, el usuario prefiere primero una ronda de feedback/alineación.

### Monetización y lanzamiento: datos concretos ya definidos

- **Google Play Store**: USD 25 pago único (cuenta de desarrollador) + período de prueba cerrada obligatorio (~14 días con usuarios mínimos) antes de publicación abierta.
- **Apple App Store**: USD 99/año (Apple Developer Program) + testeo previo vía TestFlight.
- **AdMob** (si se usa en la versión Free): la ganancia de anuncios es para el desarrollador, Google paga un porcentaje por vista/clic.
- **Precio de referencia de la suscripción PRO** (mockup, no implementado): evolucionó de USD 3–5/mes a **$15.000 ARS/mes o USD 12/mes**; botón de pago pensado para Mercado Pago/Stripe, sin integrar todavía.
- **Botón de sugerencias/feedback**: uno general (menú principal/perfil) para ideas de sistema, y opcionalmente uno específico por solapa técnica (ícono 💬) para feedback puntual — no implementado.
- Práctica de backup recomendada además de Git/GitHub: copia periódica en `.zip` de la carpeta `lib/` en disco externo o Drive personal, como red de seguridad adicional.

### Módulo Core: Dashboard como "Centro de Control y Permisos"

`ObrasListScreen` está funcionalmente definida como la raíz del sistema (Root/Home), no solo un listado: debe resolver autenticación, enrutamiento de proyectos, asignación dinámica de roles y generación de accesos por QR. Hoy solo implementa el listado visual — el resto es la brecha respecto a la sección "Permission model" de este documento.

**Roles de proyecto** (más granulares que el `UserRole` actual en `core/segurity/user_context.dart`): `admin_maestro`, `profesional`, `constructor`, `cliente_principal`, `invitado_veedor`, `invitado_apoderado`.

**Reglas de visibilidad por rol** (mapeo funcional para cuando se conecte `UserContext`/`PermisosModulo` a las pantallas):
- **Caja Blanca (100%)** — `admin_maestro`, `profesional`: edición total de cómputos, APU, precios, coeficientes y aprobaciones.
- **Vista Operativa (sin montos)** — `constructor`/capataz: cómputos y avance diario, sin valores monetarios ni márgenes.
- **Caja Negra Comercial** — `cliente_principal`: totales por rubro, avances, certificados y reportes ejecutivos, sin APU ni coeficientes internos.
- **Caja Negra Básica (lectura pasiva)** — `invitado_veedor`: solo lectura de avances físicos y fotos.
- **Invitado Apoderado** — hereda la vista del cliente, pero desbloquea firma/aprobación de certificados dentro de rangos de fecha y monto autorizados por el titular (Panel de Delegación de Firma, con registro en el Audit Log).

**Esquema de datos funcional** (no reflejado aún en `data/models/`): tabla de relación `ProyectoUsuarios` (`obraId`, `usuarioId`, `rolProyecto`, `permisosEspeciales` con `puedeAprobarCertificados`, `puedeVerApu`, `delegacionTemporalInicio/Fin`, `topeMontoAprobacion`).

**Decisión tomada**: el QR de vinculación multidispositivo (espejar sesión celular↔PC/tablet, o compartir rol con un colaborador) **no** va en el Dashboard principal — rompería la limpieza visual. Va en Configuración Global de la cuenta o en Ajustes de cada obra.

**Comportamientos adicionales documentados (ninguno implementado hoy)**:
- **Inicio abierto**: cualquier actor (Cliente, Profesional o Constructor) puede iniciar un proyecto — no hay un único punto de entrada obligado.
- Al crear una obra, el creador queda **por defecto como Administrador**, con opción de cambiarlo después.
- Tras el alta, la app debería **redirigir automáticamente** a la ventana de gestión de permisos de esa obra (hoy el alta solo cierra el modal y agrega la obra a la lista).
- **Notificación al Admin**: cuando un colaborador con permiso de edición hace una acción sensible (modificar cómputo, avance), debe generarse una alerta automática al Administrador.
- **Control de acceso obligatorio**: bloquear la navegación a cualquier solapa si no hay una obra seleccionada/creada.

### Alta de Nueva Obra: rediseño a wizard de 2 pasos

Versión superadora acordada para reemplazar el modal único actual (que hoy sufre overflow y ya fue parcheado con scroll, ver commits "solucion overflow..."):
- **Paso A — Datos técnicos**: nombre, superficie (m²), tipo de obra, moneda base.
- **Paso B — Subpantalla "Matriz de Permisos y Roles"**: asignación visual de actores desde el momento de creación de la obra — Propietario/Cliente (lectura y auditoría de avance), Arquitecto/Director (edición técnica, cómputos y carga), Empresa/Constructor (carga de avance y costos reales). El objetivo es que la trazabilidad de seguridad quede garantizada desde que se crea la obra, no agregada después.

### CTA de "Servicios Especiales": banner dinámico multiestado

El acceso a servicios técnicos (cómputo métrico, presupuesto operativo/CAC, térmico IRAM, legajo de detalles constructivos) es el **motor de monetización directa** de la plataforma — por eso no puede depender de un ícono oculto. Diseño acordado para la card de obra (banner en la parte inferior, ya con estructura base implementada en `_abrirModalServiciosEspeciales` de `obras_list_screen.dart`, pendiente el copy exacto por estado):
- **Estado neutro**: "+ Cargar Planos / Solicitar Estudio Técnico".
- **Estado "En Revisión"**: "⏳ Documentación enviada - Evaluación técnica en proceso".
- **Estado "Presupuestado"**: "📄 Presupuesto disponible - Ver desglose y anticipo (50%)".

**Flujo funcional completo** (backend no implementado): el usuario adjunta planos y tilda servicios → un evento de backend dispara en paralelo (a) un email/push automático de confirmación al cliente y (b) una alerta interna con resumen estructurado (obra, m², servicios tildados, link al archivo) → revisión técnica manual de completitud, con devolución si falta documentación → al aprobar, la obra pasa a estado "En Evaluación/Presupuestado" y se habilita el pago del **anticipo del 50%**, con el 50% restante contra entrega de la documentación final.

### Roadmap: marketplace interno de terceros (no implementar todavía)

Visión a futuro para poder tercerizar el trabajo técnico (cómputos, legajos, térmicas) sin reescribir la app — dejar la arquitectura de datos abierta a esto, sin construir la lógica ahora:
- Patrón Provider/Adapter: una tarea pasa de modo directo (la resuelve el `creadorId`/admin) a un objeto genérico `JobTask` que puede tener estado `internal` u `outsourced`.
- Campos opcionales a futuro en el modelo de tarea/presupuesto: `asignadoA_id` (profesional externo), `costoTercero`, `estadoRevision` (`pendiente_admin` / `en_proceso_tercero` / `aprobado_final`).
- Plantilla maestra de entregables (Templates Schema): valida automáticamente que lo que sube un tercero cumpla un formato mínimo antes de llegar a revisión final o al cliente; si no cumple, el bot lo rechaza.
- Bolsa de trabajos técnicos con sistema de puja entre profesionales — solo como mockup/pantalla deshabilitada por ahora, no funcional.

Advertencia explícita del propio análisis: no codificar la interfaz de subastas ni los flujos de pago a terceros en esta etapa — desviaría esfuerzo del objetivo actual (estabilizar el MVP). Mantener estos campos como opcionales/nullable para no añadir complejidad ni queries innecesarias mientras el marketplace no está operativo.

### Blindaje legal (pendiente, a tener en cuenta al tocar auth/contenido de usuario)

- **T&C / EULA de aceptación obligatoria** (checkbox opt-in en registro): exime a ComputoPRO de responsabilidad por firmas o planos no validados explícitamente por un profesional matriculado, y prohíbe expresamente contenido ilícito (documentación falsificada, planos adulterados, mensajes agraviantes).
- **Moderación de contenido**: filtro automático de texto/metadatos en campos editables por el usuario, más un mecanismo de baneo rápido a nivel de base de datos (`isBlocked = true`).
- **Audit Log inalterable**: registrar `user_id`, `timestamp`, IP y acción realizada en toda operación relevante, para poder demostrar qué usuario introdujo un contenido problemático y deslindar de responsabilidad civil/penal a la plataforma.

### QR de vinculación multiplataforma (Móvil ↔ PC/Tablet): arquitectura técnica

Complementa la "Decisión tomada" de más arriba (el QR no va en el Dashboard) con el diseño técnico de cómo debería funcionar una vez implementado. **Caso de uso principal aclarado por el usuario**: está pensado para el usuario al que le incomoda trabajar desde el teléfono — le permite hacer la carga/edición desde una PC o tablet, y que esos cambios se reflejen automáticamente en el celular (no al revés únicamente; es una sincronización real, no solo un espejo de solo lectura).
- **Generación**: QR de sesión única cifrada (token temporal de autenticación).
- **Canal**: al escanear, se valida la credencial y se abre un canal de comunicación en tiempo real (WebSocket o Firebase Realtime Database, según la transcripción original) entre el móvil y la PC/tablet — **a re-evaluar**: el backend ya decidido es Supabase (ver más abajo), que también ofrece canales realtime propios; no asumir Firebase sin confirmarlo con el usuario.
- **Sincronización bidireccional permanente**: cualquier cambio hecho en un dispositivo (tildar un rubro, ajustar un cómputo, actualizar avance) se refleja instantáneamente en el resto de las sesiones vinculadas.
- **Offline-first**: en el móvil, las mutaciones se guardan localmente (SQLite/Hive) y se sincronizan solas al recuperar conectividad — pensado para obras con mala señal en el terreno.

**Riesgos técnicos identificados (evaluación honesta del propio análisis, sin resolver aún)**:
- Resolver conflictos con **Last-Write-Wins (LWW) puro es riesgoso** para cómputos métricos concurrentes (ej.: capataz y calculista editando el mismo rubro casi al mismo tiempo pueden pisarse el dato sin aviso). Recomendado: reemplazar por un registro de conflictos por campo o un historial visual de cambios en vez de sobrescribir en silencio.
- **Riesgo de rendimiento en Flutter** al desplegar +50 rubros con subítems: exige renderizado perezoso estricto (`ListView.builder`/`SliverList`) y gestión de estado granular (Provider/Riverpod/Bloc) — hoy el proyecto no usa ninguna librería de estado (ver "Data flow" más abajo), así que esto es un cambio de arquitectura pendiente, no solo de UI.
- **Requisito explícito de hardware objetivo**: la app tiene que correr bien en celulares y sistemas operativos de **5+ años de antigüedad** (gama baja), no solo en equipos modernos — condiciona cualquier decisión de rendimiento (evitar rebuilds innecesarios, listas virtualizadas, no cargar los +50 rubros completos en memoria de una vez, cuidado con animaciones/efectos pesados).
- El catálogo base de rubros debería distribuirse **pre-cargado con la app** (JSON/SQLite estático empaquetado), no vía llamadas de red, para no depender de conectividad para mostrar el catálogo.

### Solapa 1 (Cómputo y Presupuesto): catálogo de +50 rubros y estrategia de UX

- **6 Macrorrubros** de origen: 1) Trabajos Preliminares y Tierra, 2) Estructura y Albañilería Húmeda, 3) Construcción en Seco y Sistemas Mixtos (Steel Frame / Wood Frame / placas tipo Durlock / estructuras metálicas), 4) Instalaciones y Redes, 5) Terminaciones y Revestimientos, 6) Obras Exteriores y Complementarias.
- **Bibliografía/fuentes de referencia obligatorias** para cargar rubros, subítems, APU y análisis de precios (regla del usuario, no opcional): el libro *"Cómputos y Presupuestos"* de **Chandías**, libros y planillas de cómputos y presupuestos recomendados por universidades argentinas de **ingeniería civil/en construcciones** y de **arquitectura**, la **Revista Vivienda** (Argentina) y material de la **Cámara Argentina de la Construcción (CAC)**. Cualquier carga o ampliación del catálogo de rubros/APU debe poder trazarse a estas fuentes, no inventarse ad hoc.
- **Estrategia de UX acordada** para no saturar la pantalla con +50 rubros expandibles: combinar agrupación jerárquica por macrorrubro + chips de filtro rápido en la parte superior + buscador con carga progresiva (lazy loading vía `ListView.builder`). Complementario y opcional: un wizard de 3 preguntas al crear la obra (sistema constructivo principal / si incluye demolición / qué instalaciones aplican) que pre-filtra los rubros relevantes, dejando "mostrar catálogo completo" como opción manual.
- **Free vs. Pro a nivel de rubro**: Free solo tilda/destilda rubros y subítems del catálogo fijo; Pro puede crear, editar y eliminar rubros/subítems personalizados.
- **Campos por subítem**: checkbox de activación, descripción, unidad de medida, cantidad/cómputo métrico (input directo o calculadora Largo×Ancho×Alto), precio unitario (output, viene de la Solapa 2/3 vía APU) y subtotal + % de incidencia (outputs).
- **Vínculos bidireccionales**: recibe el precio unitario desde la Solapa 3 (que a su vez deriva del APU de la Solapa 2 + coeficientes); envía las cantidades tildadas a la Solapa 4 (Gestión de Obra, para cronograma y certificación de avance) y a la Solapa 6 (Resumen Final).

### Mapa objetivo de las 6 solapas (difiere del orden/alcance actual en código)

La versión funcional acordada reordena y amplía el alcance de las solapas respecto a lo que hoy tiene `PresupuestosScreen` (hoy: `1. Cómputo y Pres.` / `2. APU` / `3. Materiales y MO` / `4. Proveedores` / `5. Certificación` / `6. Resumen Final`):

1. **Cómputo y Presupuesto** — entrada de datos base (sin cambios de posición).
2. **Análisis de Precios Unitarios (APU) & Insumos** — la "receta teórica": rendimientos de materiales, mano de obra y equipos.
3. **Materiales y Mano de Obra** — precios reales de mercado mes a mes + coeficiente K + incrementos (gastos generales, beneficio, IVA). Es el "motor de actualización de precios", separado a propósito de la receta del APU para poder actualizar toda la obra cambiando una sola lista mensual sin tocar las recetas.
4. **Gestión de Obra** — planificación, cronograma, curva de inversión, avance físico/financiero, acopios, redeterminaciones y adicionales, **incluyendo certificación** (más amplio que la actual solapa 5 "Certificación" del código). **El usuario confirmó explícitamente que esta es una de las solapas más importantes y que el renombre "Certificación" → "Gestión de Obra" es una decisión tomada**, a aplicar en el código a futuro (ver detalle de permisos y vínculos más abajo).
5. **Proveedores** — cotizaciones, órdenes de compra, acopios en corralones, control de entregas (pasa de posición 4 a 5).
6. **Resumen** — reportes, exportación PDF/Excel y portal cliente/QR (sin cambios de posición).

Dato relevante para el código: ya existe `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` (nombre alineado a este mapa objetivo) junto con `analisis_precios_tab.dart`, `mano_obra_tab.dart`, `proveedores_tab.dart` y `resumen_tab.dart`, pero **`PresupuestosScreen` no usa ninguno de esos archivos** — construye el contenido de las solapas 2 a 6 con métodos `_build*` privados inline y mantiene el orden/alcance viejo. Es la misma clase de brecha de integración ya señalada en "Data flow: two coexisting patterns".

### Gestión de Obra: permisos y vinculaciones documentados hasta ahora (a confirmar con el usuario)

El usuario pidió verificar si la lógica de vinculaciones y permisos que tenía pensada para esta solapa ya está capturada en los resúmenes anteriores. Esto es lo que hay documentado en este archivo hasta el momento — falta confirmación explícita de que sea completo:
- **Contenido de la solapa**: planificación, cronograma, curva de inversión, avance físico/financiero, acopios, redeterminaciones, gestión de adicionales y certificación de obra.
- **Vinculación de datos**: recibe de la Solapa 1 el catálogo de subítems tildados con sus cantidades (para armar cronograma y base de certificación de avance); alimenta al Audit Log cada aprobación de certificado/adicional; sus certificados aprobados alimentan el resumen ejecutivo que ve el Cliente y, eventualmente, la Solapa 6 (Resumen Final).
- **Permisos por rol** (de la matriz consolidada más abajo, aplicados a esta solapa específicamente):
  - Admin Maestro / Profesional: edición total — cronograma, carga de avance, aprobación de certificados y adicionales sin restricción.
  - Constructor/Capataz: carga diaria de avance físico y consumo de materiales; sin acceso a montos; puede *solicitar* la aprobación de un certificado pero no aprobarlo él mismo.
  - Cliente/Propietario Principal: lectura de avance y certificados; tiene la aprobación final de certificados y adicionales.
  - Invitado Veedor: solo lectura pasiva del % de avance y galería de fotos/bitácora.
  - Invitado Apoderado: puede aprobar certificados y adicionales *dentro del alcance y tope de monto* que le delegó el Cliente (permanente o temporal), con registro obligatorio en el Audit Log.

**Pendiente**: si esto no coincide con la lógica completa que el usuario tenía en mente (por ejemplo, reglas más finas de quién puede modificar un cronograma ya aprobado, cómo se gestionan específicamente los adicionales de obra, o el flujo de acopios/redeterminaciones paso a paso), hay que subir ese texto aparte para ampliar esta sección — no inventar esos detalles sin esa confirmación.

### Solapa Proveedores: base de datos obligatoria en Supabase y monetización por membresías

- A diferencia del resto de las solapas, donde Supabase es la decisión de backend general "a futuro" (ver más abajo), el usuario definió que **Proveedores requiere sí o sí su propia base de datos en Supabase**, no queda como pendiente genérico junto con las demás.
- **Nueva línea de monetización**: se prevén **membresías pagas para proveedores** (corralones, distribuidoras, hormigoneras, etc.) que quieran figurar/cotizar dentro de esta solapa, administradas mediante un bot (alta, cobro y gestión — mecánica exacta todavía sin definir). Esto concreta el ítem ya anotado en "Posicionamiento y modelo de negocio" sobre integrar proveedores como canal B2B: acá el mecanismo elegido es membresía + bot, no publicidad ni comisión por transacción.
- **Modelo de doble motor de precios** (spec histórica, detalla el mecanismo de esa monetización): (1) corralón adherido con canon/suscripción activa → un bot/API sincroniza su stock y precios en tiempo real o cada 24 hs; (2) si no hay corralón adherido en la zona de la obra → algoritmo de fallback que calcula un promedio sobre 3 proveedores predefinidos de la región, para garantizar que la solapa **nunca muestre una lista vacía**.
- **Ranking de proveedores** tipo Mercado Libre: por relevancia, menor precio o cercanía geográfica.
- Segunda vía de monetización dentro de la misma solapa: **"Corralón Destacado"**, publicidad orgánica paga sin saturar la UX (además de los cánones de membresía).
- Nota de código: `proveedores_tab.dart` ya existe en `lib/presentation/obra_detalle/tabs/` pero no está conectado a `PresupuestosScreen`, y hoy es solo una **lista estática hardcodeada de 3 proveedores de ejemplo**, sin persistencia, sin ranking, sin ningún motor de precios (ver "Mapa objetivo de las 6 solapas", "Data flow: two coexisting patterns" y "Verificación de implementación" más abajo).

### Backend planificado: Supabase

El usuario ya tiene creada una cuenta de **Supabase**, destinada a alojar las bases de datos que se necesiten para las distintas solapas (catálogo de rubros/APU/insumos, usuarios y roles por obra, documentación de servicios especiales, etc.) cuando se implemente la persistencia real. **Todavía no está integrado en el código**: `pubspec.yaml` no tiene el paquete `supabase_flutter` (ni ningún cliente de Supabase) y `services/apu_database_service.dart` sigue siendo un stub en memoria. Al planificar la capa de persistencia, Supabase es la opción de backend ya decidida — no proponer otro proveedor (Firebase, backend propio, etc.) sin que el usuario lo pida explícitamente.

Detalle ya definido en la spec histórica: **PostgreSQL, plan gratuito, región `sa-east-1` (São Paulo)** — elegido explícitamente sobre Firebase por permitir consultas relacionales más ordenadas para este dominio (rubros↔APU↔insumos↔obras↔usuarios son datos altamente relacionales, no documentales).

### Rol Invitado/Observador (Veedor) y sub-rol Apoderado: mecánica completa

Amplía la fila "Invitado" de la sección de roles de más arriba:
- **Invitado Veedor (por defecto)**: lectura pasiva de avance físico por macrorrubro, galería de fotos/bitácora, certificados aprobados (resumen ejecutivo) y estado/ubicación de la obra. Sin edición, sin aprobación, sin ver APU/costos/coeficiente K, no puede invitar a terceros. Se invita desde el Dashboard: "Agregar Integrante / Generar QR" → elegir categoría (Cliente / Profesional / Constructor / Invitado) → QR de lectura directa o enlace único (WhatsApp/Email).
- **Invitado Apoderado (delegación explícita del Cliente/Propietario Principal)**: el Cliente Principal configura, desde su panel en el Dashboard, una delegación de firma hacia un invitado puntual — **permanente o temporal** (rango de fechas), con alcance configurable: aprobar certificados de avance, aprobar adicionales hasta un **monto límite**, y opcionalmente modificar cómputos métricos. Pensado como contingencia para cuando el titular no tiene señal o está de viaje: la interfaz del invitado pasa dinámicamente de solo-lectura a mostrar los botones de aprobación. Toda aprobación delegada queda en el Audit Log con formato tipo: *"Certificado N° 3 aprobado el 22/10/2026 por María Gómez (Apoderada autorizada por el Propietario Juan Pérez el 14/10/2026)"*.

**Matriz de permisos consolidada** (columnas: Cómputo y APU / Avance físico y fotos / Modificación de precios / Aprobación de certificados / Nivel de visibilidad):
- Admin Maestro y Profesional → edición total en todo → Caja Blanca (100%).
- Constructor/Capataz → lectura de cómputo, carga diaria de avance, sin acceso a precios, solo puede *solicitar* aprobación → Vista Operativa (sin montos).
- Cliente/Propietario Principal → lectura de cómputo, lectura de avance, sin acceso a APU, aprobación final de certificados → Caja Negra Comercial.
- Invitado/Observador → sin acceso a cómputo/APU, solo lectura pasiva de avance, sin precios ni aprobaciones → Caja Negra Básica (Lectura), salvo que tenga una delegación de Apoderado activa.

### Selector de roles al crear/configurar la obra (Dashboard)

Complementa el Paso B (Matriz de Permisos y Roles) del wizard de alta de obra descripto arriba: quien crea la obra —puede ser el Cliente, el Profesional o el Constructor indistintamente, la app no fuerza un único punto de entrada— define mediante checkboxes/switches qué roles están activos y quién asume cada uno ("Mi perfil" o "Invitar por Email/QR" para Propietario, Profesional y Constructor). El motor de permisos ajusta automáticamente la visibilidad según la combinación resultante. Casos de uso previstos:
- **Rol único** (autoconstructor o profesional que hace todo): tilda los 3 roles en su propio usuario → acceso 100% sin restricciones.
- **Profesional invita a un Cliente**: el profesional, como Admin, puede tildar "ocultar APU" y/o "ocultar Coeficiente K / beneficios" antes de generar el QR/enlace de invitación — el cliente entra en modo Caja Negra.
- **Cliente inicia solo y luego contrata a un Profesional**: el cliente crea la obra en modo Free/Pro haciendo un cómputo de tanteo con solo el rol Propietario tildado; al contratar, tilda "Asignar Profesional", genera el QR/enlace y le transfiere la Dirección Técnica — el profesional recibe lo ya cargado por el cliente y desbloquea la edición fina de APU/coeficientes sobre esa base.

### Metodología de trabajo para las 6 solapas

Antes de escribir código de cualquier solapa nueva, el usuario prefiere cerrar primero toda la arquitectura de información: propósito, inputs/outputs, vínculos entre solapas y vista por rol (Profesional/Constructor/Cliente) de las 6 solapas + Dashboard, consolidarlo en un documento único, y recién después pasar a la implementación (consistente con la sección "Reglas de edición" de arriba). Orden de trabajo acordado: Dashboard + Solapa 1 → Solapa 2 (APU) → Solapa 3 (Materiales y MO) → Solapa 4 (Gestión de Obra) → Solapa 5 (Proveedores) → Solapa 6 (Resumen).

### Colores institucionales: #1B365D implementado ad hoc, pero no centralizado en el theme

- **#1B365D** (azul institucional) está efectivamente en uso, hardcodeado inline en 9 archivos de `presentation/` (`obras_list_screen.dart`, `presupuestos_screen.dart` y la mayoría de los `tabs/*.dart`). El acento dorado/ámbar (`Colors.amber`) también está en uso; el acento alternativo citado en la spec (**#E07A5F**) no aparece en el código.
- **Discrepancia real**: `lib/config/app_theme.dart` (`AppTheme.lightTheme`, el único `ThemeData` que usa `MaterialApp` en `main.dart`) define un `ColorScheme.fromSeed` con semilla **#1E88E5** (azul) y secundario **#26A69A** (verde azulado) — colores completamente distintos al #1B365D "oficial". El fondo de tarjetas/pantallas también difiere levemente del valor de la spec (`scaffoldBackgroundColor: #F4F6F8` en el theme vs. `#F5F7FA`/`#F8F9FA` documentados, y varias pantallas usan además su propio `#F4F6F9` inline).
- **Conclusión práctica**: el "look" institucional real de la app hoy depende de que cada pantalla hardcodee `Color(0xFF1B365D)` por su cuenta, no del theme centralizado — que de hecho define una paleta distinta y sin uso visible. Si en algún momento se centraliza el theming, `AppTheme.lightTheme` debería adoptar #1B365D como `primary`/seed, no los colores actuales.

### Verificación de implementación: funcionalidades clave pedidas por el usuario

Chequeado contra el código real de `lib/` (no contra lo que dicen los documentos). Ninguna de estas funcionalidades tiene entidad de datos, servicio ni UI hoy salvo donde se indique lo contrario:

- **Ciclo de vida del Certificado de Obra (5 estados)** — definición completa: 1) *Borrador* (carga de avances por Profesional/Empresa), 2) *Emitido/Esperando Pago* (notifica al Propietario con fecha límite según plazo pactado), 3) *Leído por Propietario* (se notifica a la obra automáticamente al abrirse), 4) *Pagado por Propietario* (marca medio de pago + adjunta comprobante), 5) *Impactado y Cerrado* (la Empresa/Constructor verifica el cobro y adjunta factura final). Reglas especiales: el plazo de pago se configura **una sola vez antes del Certificado N°1** y aplica a todos los siguientes; si se opta por firma física, el sistema debe **bloquear la emisión del siguiente certificado** hasta subir el PDF/imagen firmado.
  **Estado real**: `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` implementa solo **3 de los 5 estados** (`Borrador` → `Emitido (Esperando Pago)` → `Pagado`, ver `_cambiarEstado`/`_getColorEstado`). Faltan por completo *Leído por Propietario* y *Impactado y Cerrado*. Hay un botón "Subir PDF Firmado" pero **no bloquea** la emisión del siguiente certificado. No hay Fondo de Reparo. No se genera ningún PDF real (los paquetes `pdf`/`printing` siguen sin usarse en todo `lib/`). El plazo de pago (`_diasPlazoPago`) es un campo fijo sin UI para configurarlo. Y el tab **no está conectado** a `PresupuestosScreen` (usa un `obraId` requerido que nadie le pasa hoy).
- **Matriz de permisos por tipo de relación cliente-obra** — 3 relaciones con visibilidad distinta: *Cliente Autoconstructor* (ve todo, costos directos y precios reales de corralón), *Cliente con Profesional + Contratista* (ve precio final y avance; oculto: salarios, gastos generales, beneficio, imprevistos y precios negociados en bruto — solo Profesional/Contratista cargan, Cliente aprueba en modo lectura), *Cliente con Contratista Directo sin Profesional* (visibilidad más restringida aún: ve avance y precio del rubro certificado, oculto el costo interno y margen del contratista).
  **Estado real**: **no implementada**. `gestion_obra_tab.dart` solo tiene un `DropdownButton` binario (`'Profesional / Empresa'` vs `'Propietario / Cliente'`) sin relación con estos 3 casos, y el resto del código no modela ningún concepto de "tipo de relación cliente-obra".
- **Motor "Mandar a Presupuestar"** (botón inteligente en Resumen Final) — dispara una solicitud zonal simultánea a 3 corralones geolocalizados en la zona de la obra; los precios devueltos se muestran etiquetados como no firmes hasta una validación manual obligatoria ("Validar y Confirmar Precios"); exportación alternativa a PDF/Excel/texto WhatsApp; si no hay comercios con membresía activa en la zona, calcula un promedio automático sobre 1 a 4 proveedores de referencia.
  **Estado real**: **no implementado**, ningún archivo del proyecto lo referencia. `resumen_tab.dart` solo calcula y muestra el desglose de costos/coeficientes, sin ningún botón ni lógica de cotización a proveedores.
- **Modo "Carga Externa"** (transversal a varias solapas) — permite ingresar presupuestos cerrados o montos "llave en mano" sin pasar por el desglose de APU, pensado para quien solo necesita gestión y no cálculo técnico; al activarlo debería ocultar los enlaces a APU y habilitar directamente la Solapa de Gestión de Obra para arrancar el control de avance.
  **Estado real**: **no implementado**, sin ninguna referencia en el código.

### Otras brechas relevantes detectadas al verificar contra la spec histórica

- **Solapa 2 (APU): confidencialidad y Coeficiente K aislado** — la spec exige que el Constructor no tenga acceso a esta solapa (o solo vea cómputo sin precios teóricos) y que el Coeficiente K quede aislado y privado en la Solapa 3, incluso para el Profesional en otras vistas. **Estado real**: no implementado — el concepto de Coeficiente K no existe en ningún archivo de `lib/` (búsqueda sin resultados), y no hay ninguna restricción de acceso por rol entre solapas.
- **Matriz heredable de coeficientes indirectos (Solapa 2)** — Gastos Generales, Imprevistos y Beneficio se definirían **una sola vez a nivel obra** y se heredarían automáticamente a todas las planillas de APU (con posibilidad de que un usuario Pro los sobreescriba puntualmente en un ítem de mayor riesgo), más un ítem de EPP (1%) e impuestos siempre editables por provincia (IVA 21%, IIBB 3-5%, Ganancias aparte). **Estado real**: `resumen_tab.dart` tiene sliders de Gastos Generales/Imprevistos/Beneficio, pero son **globales de esa solapa únicamente** (no heredables por ítem de APU — de hecho no hay APU por ítem en el código), sin EPP, sin distinción Free/Pro y sin desglose de impuestos por provincia.
- **Solapa 3 (Materiales y Mano de Obra): escala UOCRA y zonificación** — se espera una escala salarial UOCRA completa (Oficial Especializado, Oficial, Medio Oficial, Peón) actualizada mensualmente según paritarias oficiales, un catálogo de +200 insumos frecuentes, y checkboxes de zonificación geográfica con explicación de a qué zona corresponde cada selección. **Estado real**: `mano_obra_tab.dart` tiene una lista de ejemplo de un puñado de operarios con categoría/valor-hora/horas trabajadas — sin las 4 categorías UOCRA completas, sin actualización mensual, sin zonificación, y sin catálogo de insumos (ese catálogo vive aparte, sin relación, en `data/models/base_insumos_seed.dart` con solo 6 ítems de ejemplo).
- **Lógica Free vs. Pro transversal** — se espera que Free opere con catálogo estándar y coeficientes bloqueados de solo lectura + exportación con marca de agua, y que Pro habilite edición libre con un cartel de advertencia de responsabilidad técnica (silenciable por solapa, recordado por usuario) + exportación limpia con marca propia. **Estado real**: solo existe un booleano `_esPlanPro` local a `ObrasListScreen`, sin persistencia, que únicamente desbloquea el campo de cotización USD personalizada y cambia el badge PRO/FREE — no afecta a ninguna otra solapa, no bloquea nada, y no hay ninguna lógica de exportación PDF con o sin marca de agua (los paquetes `pdf`/`printing` siguen sin uso).

### Divergencia con la Clean Architecture documentada

La spec histórica describe una Clean Architecture "ya implementada" con capa `domain/` (entities, contratos de repositorios, usecases) separada de `data/`. **El repo actual no tiene esa carpeta** — la estructura real es la que se documenta en "Directory layout" más abajo (`config/`, `core/`, `data/`, `presentation/`, `services/`, sin `domain/`). No asumir que existe una capa domain/usecases al planificar trabajo nuevo; introducirla sería trabajo nuevo, no algo que "recuperar".

### Roadmap adicional pospuesto (no construir todavía)

Complementa el roadmap del marketplace de terceros de más arriba:
- **Geolocalización personalizada** por obra y por usuario (insumo directo del motor de proveedores/corralones descripto arriba).
- **Registro de obra con segmentación de perfil**: guardar el perfil de quien crea la obra (Profesional/Constructor/Cliente) no solo para permisos, sino para que el propio usuario reciba métricas/alertas de uso de la plataforma — pensado originalmente vía bot de Telegram o notificación interna.

## Commands

```
flutter pub get              # install dependencies
flutter run                  # run on connected device/emulator (Windows desktop, Android, etc.)
flutter analyze              # static analysis (uses analysis_options.yaml -> flutter_lints)
flutter test                 # run all tests
flutter test test/widget_test.dart   # run a single test file
```

There is currently only one test (`test/widget_test.dart`), a smoke test that pumps `MiAppApu` and checks a `MaterialApp` is found. No test infrastructure (mocks, golden tests) exists yet.

`flutter analyze` currently reports ~20 pre-existing lint infos (deprecated `withOpacity`, missing `super.key`, an undeclared `intl` dependency used transitively). These are known and not regressions to fix incidentally — only fix lints in files you're already substantially editing.

Historical note from the pre-migration (Gemini-era) docs: recurring Gradle build failures (`assembleDebug failed`) tied to the Android Gradle Plugin (AGP) version and the `file_picker` package, with a recommendation to update AGP to ≥8.11.1 or replace `file_picker` with `file_selector`. **`file_picker` is not currently a dependency in `pubspec.yaml`**, so this specific issue may not apply to the current state — worth remembering only if file-picking functionality gets added later.

## Architecture

### Entry point and routing

`lib/main.dart` builds the `MaterialApp` and defines routes directly via `onGenerateRoute` (routes: `/` → `ObrasListScreen`, `/presupuesto` → `PresupuestosScreen`). **`lib/config/routes.dart` (`AppRoutes`) is not wired into `main.dart` and is currently dead code** — don't assume routing changes there take effect; update `main.dart`'s `onGenerateRoute` instead, or wire `AppRoutes` in if consolidating.

### Directory layout

```
lib/
  config/        # theme (AppTheme) and unused AppRoutes
  core/
    segurity/    # UserContext / UserRole permission model (note: "segurity" typo, not "security")
    utils/       # CurrencyFormatter and other stateless helpers
  data/models/    # plain Dart model classes (no codegen — manual toMap/fromMap/copyWith)
  presentation/
    dashboard/    # ObrasListScreen (list of obras, entry screen)
    obra_detalle/
      screens/    # PresupuestosScreen (tabbed detail view for one obra)
      tabs/       # one file per tab shown inside PresupuestosScreen
  services/       # ApuDatabaseService — in-memory stub, NOT a real database despite the name
```

No `domain/` layer exists (no entities/usecases/repository-contracts folder) — see "Divergencia con la Clean Architecture documentada" in the functional spec section above; a historical doc claims one was already built, but it isn't in this repo.

### Data flow: two coexisting patterns

The codebase is mid-migration between two ways of representing an "obra":

1. **Typed models** (`data/models/obra_model.dart`, `rubro.dart`, `subitem.dart`, etc.) with `toMap`/`fromMap`/`copyWith`, used by `RubrosTab`.
2. **Raw `Map<String, dynamic>`** obra records constructed ad hoc inside `ObrasListScreen`'s local `_obras` list state, passed by reference through `Navigator.push` to `PresupuestosScreen`.

`PresupuestosScreen` accepts `dynamic obra` and handles *both* shapes: it type-checks for `Map<String, dynamic>` vs. falls back to reflective `dynamic` field access wrapped in `try { ... } catch (_) {}` for an `ObraModel` (see `_PresupuestosScreenState.initState`). When touching this screen, preserve both code paths unless you're deliberately finishing the migration to `ObraModel` everywhere.

No state management library is used (no Provider/Riverpod/Bloc/get_it) — state lives in `State` objects via `setState`, and data is passed down through widget constructors / `Navigator` arguments. `services/apu_database_service.dart` returns a hardcoded in-memory list and is not currently consumed by `ObrasListScreen` (which keeps its own separate hardcoded `_obras` list) — treat it as an incomplete integration point, not a source of truth.

### Permission model (not yet wired to UI)

`core/segurity/user_context.dart` defines `UserRole` (adminMaestro, profesional, constructor, clientePrincipal, veedor, apoderado) and `UserContext` with visibility getters (`puedeVerMontosYAPU`, `esVistaOperativa`, `puedeAprobarCertificados`). `data/models/obra_model.dart` separately defines `CapaVisibilidad` and `PermisosModulo` (per-obra granular permissions: `verComputo`, `verPreciosFinales`, `verApuYCoeficienteK`, `cargarAvanceFisico`, `editarComputo`, `aprobarCertificados`, `invitarTerceros`). These two permission systems are not yet connected to any screen's rendering logic — screens currently show all data unconditionally. When implementing role-based visibility, this is the intended seam.

### Currency and formatting

`core/utils/currency_formatter.dart` (`CurrencyFormatter.formatARS/formatUSD/formatByCurrency`) is the intended shared formatter, but most screens instead define their own local `_formatearMonto`/`_fmt` method (regex-based thousands separator, e.g. in `obras_list_screen.dart`, `presupuestos_screen.dart`, `rubros_tab.dart`) rather than reusing it. Prefer `CurrencyFormatter` in new code rather than adding another local copy.

### Screen size and structure

Screens under `presentation/` are large, self-contained `StatefulWidget`s (500–1000+ lines) that build dialogs, bottom sheets, and tab content as private `_build*` methods on the `State` class rather than extracting separate widget files. This is the established pattern here — follow it for consistency rather than pre-emptively splitting files, unless a screen grows unwieldy and the user asks for a refactor.

### Dependencies not yet used in code

`pubspec.yaml` declares `local_auth`, `pdf`, `printing`, and `path_provider`, but no file under `lib/` currently imports them — these are provisioned for planned features (biometric auth, PDF export of legajos/presupuestos) that aren't implemented yet.
