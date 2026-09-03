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
6. Cada tanda verificada en el emulador se commitea antes de arrancar la siguiente, aunque la
   siguiente parezca una corrección chica. Motivo real, no hipotético: en el costo de mano de obra
   (Paso 5, tanda 2) un bug de gate desvió varias rondas de trabajo y el commit del grupo anterior
   nunca se cerró — cuando por fin se quiso commitear, el archivo del panel ya había sido reescrito
   por la ronda siguiente (separación en dos ventanas) sin ningún commit intermedio de por medio.
   No había forma de separar limpio en dos commits sin reconstruir a mano contenido que ya no
   existía en git, con riesgo de terminar commiteando código nunca verificado — así que las dos
   etapas quedaron juntas en un solo commit grande, con el historial sin poder contar lo que pasó
   en el orden real. Commitear apenas se verifica evita que esto se repita.

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

**Roles de proyecto**: `admin_maestro`, `profesional`, `constructor`, `cliente_principal`, `invitado_veedor`, `invitado_apoderado` — viven como `RolProyecto` en `lib/data/models/obra_member.dart` (Etapa 3). El `UserRole` propio que tenía `core/segurity/user_context.dart` ya no existe: se consolidó en `RolProyecto` para no mantener dos enums paralelos.

**Reglas de visibilidad por rol** (mapeo funcional, ya reflejado en los getters de `UserContext` — falta conectarlos a las pantallas):
- **Caja Blanca (100%)** — `admin_maestro`, `profesional`: edición total de cómputos, APU, precios, coeficientes y aprobaciones.
- **Vista Operativa (sin montos)** — `constructor`/capataz: cómputos y avance diario, sin valores monetarios ni márgenes.
- **Caja Negra Comercial** — `cliente_principal`: totales por rubro, avances, certificados y reportes ejecutivos, sin APU ni coeficientes internos.
- **Caja Negra Básica (lectura pasiva)** — `invitado_veedor`: solo lectura de avances físicos y fotos.
- **Invitado Apoderado** — hereda la vista del cliente, pero desbloquea firma/aprobación de certificados dentro de rangos de fecha y monto autorizados por el titular (Panel de Delegación de Firma, con registro en el Audit Log).

**Esquema de datos: ya implementado como `obra_members`** (Etapa 3, paso 1 — el `ProyectoUsuarios` que este documento anticipaba). Tabla creada en Supabase vía `supabase/migrations/0001_obra_members.sql` y modelo Dart en `lib/data/models/obra_member.dart` (`RolProyecto`, `ObraMember`, `PermisosEspeciales`): una fila por `(obra_id, usuario_id, rol)` — roles combinables insertando varias filas para el mismo usuario+obra —, con `puedeAprobarCertificados`, `puedeAprobarAdicionales`, `topeMontoAprobacion`, `delegacionTemporalInicio/Fin`, `puedeInvitarTerceros` y `puedeVerApuAjena` (default `false`) como campos de `PermisosEspeciales`. Diseño completo y las 7 decisiones cerradas (ownership de APU por persona, `admin_maestro` como flag administrativo, etc.) en `docs/etapa3_roles_permisos_diseno_datos.md`. RLS aplicado (ver paso 5 más abajo).

**Paso 2 (Adicionales/Demasías/Quitas + Audit Log) también ya en producción.** Tablas `modificaciones_obra` y `audit_log` creadas vía `supabase/migrations/0002_modificaciones_obra_audit_log.sql`, modelos Dart en `lib/data/models/modificacion_obra.dart` (`TipoModificacion`, `EstadoModificacion` con 4 estados incluyendo `devuelto`, `ModificacionObra`) y `lib/data/models/audit_log_entry.dart` (`AuditLogEntry`). Nota técnica: `modificaciones_obra.subitem_id` y `.apu_privado_id` quedaron como `uuid` sueltos, **sin foreign key** — la tabla `subitems` real (Solapa 2) todavía no existe en Supabase, así que la FK original tirada en el diseño falló en producción (`relation "subitems" does not exist`, 42P01); agregar esas FKs con un `alter table` aparte cuando `subitems`/APU existan.

**Paso 3 (`libro_entradas`) también ya en producción.** Tabla única para los 3 libros de Gestión de Obra vía `supabase/migrations/0003_libro_entradas.sql`, modelo Dart en `lib/data/models/libro_entrada.dart` (`TipoLibro`, `LibroEntrada`), con `entrada_padre_id` autorreferenciado para modelar acuses de recibo/respuestas sin una tabla aparte.

**Paso 4.** `core/segurity/user_context.dart` migrado: `UserContext` ya no encapsula un `UserRole` global fijo, se construye a partir de las filas de `ObraMember` de un usuario en una obra puntual (`UserContext.desdeObraMembers`), con roles combinables. Los 3 getters (`puedeVerMontosYAPU`, `esVistaOperativa`, `puedeAprobarCertificados`) recalculados sobre esa lista: `esVistaOperativa` exige Constructor puro (sin ningún otro rol con visibilidad económica combinado); `puedeAprobarCertificados` incluye ahora `cliente_principal` además de `admin_maestro` y `invitado_apoderado` con delegación vigente (gap real que tenía la versión anterior, no solo un ajuste por roles combinables). Verificado con búsqueda en todo `lib/`: `UserContext` sigue sin consumidores — migración de bajo riesgo, sin conectar a ninguna pantalla todavía.

**Paso 5 (RLS) — Etapa 3 completa de punta a punta.** `supabase/migrations/0004_rls_etapa3.sql` agrega Row Level Security a las 4 tablas de Etapa 3 (`obra_members`, `modificaciones_obra`, `audit_log`, `libro_entradas`), aplicado en producción y confirmado en el dashboard de Supabase (Database → Policies). Se apoya en 3 funciones helper `SECURITY DEFINER` (`is_obra_member`, `tiene_rol_en_obra`, `puede_aprobar_monto`) en vez del patrón de dueño único que usa `obras` (`id_admin_creador = auth.uid()`), porque estas tablas tienen múltiples roles combinables por obra, no un dueño único. Decisiones de diseño relevantes: `obra_members` y `libro_entradas` tienen SELECT abierto a `is_obra_member()` completo; `modificaciones_obra` colapsa `solicitado_por`/`subido_por` al mismo usuario en el INSERT (limitación conocida y documentada inline en la migración — el schema no tiene todavía un estado intermedio para separar "quien detecta" de "quien eleva formalmente"); `audit_log` no tiene política de UPDATE ni DELETE para nadie (inalterable, ver "Blindaje legal" más abajo). **Importante**: RLS resuelve visibilidad *por fila* (a qué obra pertenecés), no *por columna* — no oculta `monto_total`/`tope_monto_aprobacion` de roles en "vista operativa sin montos" como Constructor; esa redacción sigue pendiente en capa de app, vía los getters de `UserContext`. Con este paso se cierra la implementación de Etapa 3 tal como quedó diseñada en `docs/etapa3_roles_permisos_diseno_datos.md` (datos + control de acceso a nivel de base).

**Primera conexión a UI (verificada end-to-end en producción, 2026-08-19).** `PresupuestosScreen` (`lib/presentation/obra_detalle/screens/presupuestos_screen.dart`) es la primera pantalla que consume `UserContext`/`obra_members` de verdad. En `initState` extrae el `obraId` de la obra abierta (de `widget.obra`, sea `Map` u `ObraModel`) y llama a `_cargarUserContext()`, que usa `AuthService.usuarioActual` + el nuevo `lib/services/obra_members_repository.dart` (`ObraMembersRepository.getMiembrosDeObra`, sigue el mismo patrón que `ObrasRepository` pero mapea las columnas planas snake_case de `obra_members` a `ObraMember`/`PermisosEspeciales` a mano, sin pasar por `ObraMember.fromMap`) para construir el `UserContext` real vía `desdeObraMembers`. El único efecto visible por ahora: `_buildTabApu()` (solapa "2. APU") muestra un placeholder de "sin acceso" mientras carga o si `puedeVerMontosYAPU != true`, y solo si es `true` renderiza el contenido real (todavía mock, ver más abajo). Fail-closed por diseño: sin usuario logueado, sin `obraId`, o mientras la consulta está en vuelo, no se ve el contenido. Confirmado con datos reales en producción en los dos sentidos: sin fila en `obra_members` para el usuario en esa obra → placeholder; con una fila `admin_maestro` insertada → contenido completo del APU. El resto de las pantallas (`ObrasListScreen`, las otras 5 solapas de `PresupuestosScreen`, `gestion_obra_tab.dart`, los tabs con `obraId` sin conectar) sigue sin condicionar por rol — es la extensión pendiente de este mismo mecanismo, no un problema del mecanismo en sí.

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

**Ya integrado en el código** (a diferencia de lo que documentaba una versión anterior de este archivo): `pubspec.yaml` declara `supabase_flutter: ^2.17.2`, y `lib/main.dart` llama a `Supabase.initialize()` con `SUPABASE_URL`/`SUPABASE_ANON_KEY` antes de levantar la app (ver sección "Commands" más abajo sobre `env.json`). `ObrasRepository` (`lib/services/obras_repository.dart`) ya usa `Supabase.instance.client` para las cuatro operaciones sobre la tabla `obras` (`getObras`, `crearObra`, `actualizarObra`, `eliminarObra`), traduciendo entre las claves camelCase que consume `ObrasListScreen` y las columnas snake_case de la tabla. `AuthService` (`lib/services/auth_service.dart`) y `AuthGate` (`lib/presentation/auth/auth_gate.dart`) ya usan Supabase Auth (email/contraseña) para login/logout y para gatear el acceso a `ObrasListScreen` — es la Etapa 1 del sistema de permisos, ver sección "Permission model" más abajo. Lo que sigue sin conectar a Supabase: `services/apu_database_service.dart` (catálogo de rubros/APU) sigue siendo un stub en memoria, no consume la tabla `obras` ni ninguna otra tabla real. Al seguir planificando la capa de persistencia, Supabase sigue siendo la opción de backend ya decidida — no proponer otro proveedor (Firebase, backend propio, etc.) sin que el usuario lo pida explícitamente.

Detalle ya definido en la spec histórica: **PostgreSQL, plan gratuito, región `sa-east-1` (São Paulo)** — elegido explícitamente sobre Firebase por permitir consultas relacionales más ordenadas para este dominio (rubros↔APU↔insumos↔obras↔usuarios son datos altamente relacionales, no documentales).

**Mismatch `ObraModel.id` int/uuid: resuelto.** El proyecto de Supabase tiene un esquema de tablas con `id uuid` y `gen_random_uuid()` (incluida `obras`, en el mismo estilo que `corralones`, `proveedores`, `documentos_proveedor`, `insumos`, `insumos_proveedor`, `precios`). `ObraModel.id` ya es `String` de punta a punta (commit `581d1d3`, "refactor: migrar ObraModel.id de int a String"), igual que `Rubro`, `Subitem` e `Insumo`. `ObraModel.fromMap()` castea `id` con `.toString()`, tolerando cualquier tipo de origen. El id de una obra nueva se genera del lado del servidor (`gen_random_uuid()` vía Supabase, `ObrasRepository.crearObra()` no envía `id` en el insert) — no hay generación numérica ni contador local en el código Dart. Único resabio menor, también resuelto: `mano_obra_tab.dart`, `resumen_tab.dart` y `proveedores_tab.dart` tenían `final int obraId;` en sus widgets (no conectados hoy a `PresupuestosScreen`, así que sin impacto en runtime); ya están alineados a `String`.

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
  **Estado real en `lib/` (paso 1 de conexión a UI verificado en producción por el usuario, 2026-08-21)**: `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` ya no es mock — lee la lista real de certificados de la obra desde la tabla `certificados` vía `CertificadosRepository` (`lib/services/certificados_repository.dart`) y el modelo `Certificado`/`EstadoCertificado` (`lib/data/models/certificado.dart`, mapeado 1:1 a la tabla), con estados de carga/error/vacío explícitos (vacío ≠ error). Conectado a `PresupuestosScreen`, pestaña 5 (rotulada "Gestión de Obra" — se renombró desde "Certificación" porque a futuro esa solapa va a alojar más que certificados: adicionales/demasías/quitas, los 3 libros, anticipo/fondo de reparo). Probado por el usuario contra la obra "1": caso vacío (sin certificados) y caso con un certificado en borrador insertado a mano, ambos con render correcto.
  **Sigue siendo solo lectura, deliberadamente**: se sacaron todos los botones de acción que tenía el mock (solo mutaban estado local, no persistían nada) — ninguna de las 5 funciones de transición (`emitir_certificado`, `marcar_certificado_leido`, `marcar_certificado_pagado`, `marcar_certificado_impactado`, `subir_pdf_firmado_certificado`, ver sección "Ciclo de vida del Certificado de Obra: capa de datos completa" más abajo) está conectada todavía, ni el plazo de pago (`obras.dias_plazo_pago_certificados`) tiene UI de configuración. No se genera ningún PDF real (los paquetes `pdf`/`printing` siguen sin usarse en todo `lib/`).
- **Matriz de permisos por tipo de relación cliente-obra** — 3 relaciones con visibilidad distinta: *Cliente Autoconstructor* (ve todo, costos directos y precios reales de corralón), *Cliente con Profesional + Contratista* (ve precio final y avance; oculto: salarios, gastos generales, beneficio, imprevistos y precios negociados en bruto — solo Profesional/Contratista cargan, Cliente aprueba en modo lectura), *Cliente con Contratista Directo sin Profesional* (visibilidad más restringida aún: ve avance y precio del rubro certificado, oculto el costo interno y margen del contratista).
  **Estado real**: **no implementada**. `gestion_obra_tab.dart` solo tiene un `DropdownButton` binario (`'Profesional / Empresa'` vs `'Propietario / Cliente'`) sin relación con estos 3 casos, y el resto del código no modela ningún concepto de "tipo de relación cliente-obra".
- **Motor "Mandar a Presupuestar"** (botón inteligente en Resumen Final) — dispara una solicitud zonal simultánea a 3 corralones geolocalizados en la zona de la obra; los precios devueltos se muestran etiquetados como no firmes hasta una validación manual obligatoria ("Validar y Confirmar Precios"); exportación alternativa a PDF/Excel/texto WhatsApp; si no hay comercios con membresía activa en la zona, calcula un promedio automático sobre 1 a 4 proveedores de referencia.
  **Estado real**: **no implementado**, ningún archivo del proyecto lo referencia. `resumen_tab.dart` solo calcula y muestra el desglose de costos/coeficientes, sin ningún botón ni lógica de cotización a proveedores.
- **Modo "Carga Externa de Presupuesto"** (transversal a varias solapas) — permite ingresar presupuestos cerrados o montos "llave en mano" sin pasar por el desglose de APU, pensado para quien solo necesita gestión y no cálculo técnico. Se ofrece en el Alta de Obra o inmediatamente después de crearla. Dos niveles (roadmap, no implementar todavía):
  - **Nivel 1 — Presupuesto con Plantilla**: el usuario descarga una plantilla Excel estandarizada (columnas fijas: Rubro, Descripción, Unidad, Cantidad, Precio Unitario opcional), la completa con sus propios datos y la sube. La app lee esa plantilla y puebla automáticamente `ObraModel`/`Rubro`/`Subitem`, habilitando: listado de materiales automático (cruzando contra la tabla `insumos`), cotización a proveedores/corralones cercanos (reutilizando el motor de precio promedio ya documentado en "Solapa Proveedores"), cálculo de mano de obra vía escala UOCRA, y certificaciones con datos reales en Gestión de Obra.
  - **Nivel 2 — Carga Libre**: el usuario sube su propio PDF/Excel con cualquier formato, sin adaptarse a la plantilla. La app NO puede leer ese contenido; el archivo queda solo como documento de referencia/respaldo. Al elegir este nivel hay que mostrar un aviso explícito antes de confirmar, aclarando que el usuario deberá armar manualmente: listado de materiales, solicitud de precios a proveedores y certificados de avance — la app no automatiza nada a partir de este archivo. Lo que sí queda disponible en este nivel: comunicación entre roles (Constructor/Profesional/Propietario) y carga manual básica de avance/certificados en Gestión de Obra.
  - Al activar cualquiera de los dos niveles debería ocultar los enlaces a APU y habilitar directamente la Solapa de Gestión de Obra para arrancar el control de avance.
  **Estado real**: **no implementado**, sin ninguna referencia en el código. **Superado por el diseño más nuevo del "Importador de Excel/PDF"** (ver sección más abajo) — ahí la IA sí lee el archivo (Excel/PDF/foto) y prellena un formulario, en vez del Nivel 2 "la app no puede leer esto". Este párrafo queda como registro histórico de la idea original, no como el diseño vigente.

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
- **Motor de precio de referencia por m² por zona**: al elegir/tocar una zona geográfica (radio ~50km), mostrar en el Dashboard un valor de referencia de $/m² en ARS y USD, separado en 3 categorías de obra (A, B, C según tipo de materiales/construcción). El valor debe ser el promedio REAL de las obras ya cargadas por usuarios en esa zona y categoría (derivado de `monto_total` ÷ superficie de cada obra), no un valor fijo estimado — el propósito es mostrar algo como "Valor promedio obra hoy en zona Bariloche: $X/m²". Requiere: (1) agregar `categoria` (A/B/C) a la tabla `obras` en Supabase, (2) una función SQL de promedio por cercanía geográfica + categoría, similar en patrón a `calcular_precio_promedio_insumo()` ya documentada para corralones (ver "Solapa Proveedores" más arriba). Potencial de negocio alto: dato consultado tanto por profesionales como por propietarios. Evaluar prioridad más adelante, no implementar ahora.
- **"Obra Demo de Onboarding"**: al entrar un usuario nuevo, se genera automáticamente una obra de ejemplo (marcada con flag `es_demo`) que sirve como recorrido guiado por las funcionalidades de la app. El usuario puede ocultarla desde algún sector de Configuración, y volver a mostrarla cuando quiera desde ahí mismo. Debería generarse localmente en el dispositivo, no guardarse en la tabla `obras` de Supabase, para no mezclarse con datos reales de uso.
- **"Sistema de Registro/Login de Usuarios"**: pendiente central para destrabar roles y permisos reales (`UserContext` existe en el código y ya está conectado a `PresupuestosScreen` — ver "Permission model" más arriba —, pero el resto de las pantallas todavía no). Usar Supabase Auth. A definir antes de implementar: método de registro (email/contraseña, Google, o ambos), y si se piden datos profesionales (matrícula, nombre de estudio) en el registro o se completan después en el perfil. Es la base de la que dependen: asignación de roles al crear obra, matriz de permisos por tipo de relación cliente-obra, delegación de firma, y el campo `idAdminCreador` ya reservado en `ObraModel`/la tabla `obras`.
- **Actualización automática del dólar BNA al abrir la app**: la cotización de referencia (hoy hardcodeada, ver banner del Dashboard) debe traerse de una fuente real cada vez que el usuario abre la app con conexión a internet — no en un cronograma fijo (no un cron diario/semanal). Si el valor nuevo difiere más de un 5% del último guardado, mostrar un aviso visual breve al usuario antes de aplicarlo.
- **CAC aplicado solo sobre el monto pendiente de ejecutar**: la redeterminación por índice CAC debe recalcularse únicamente sobre la porción de la obra que todavía no tiene certificación emitida. El monto ya certificado queda congelado al valor vigente en el momento de esa certificación — no se redetermina retroactivamente. Requiere que el cálculo de CAC esté conectado al estado de los certificados de la Solapa 4 (Gestión de Obra, ver ciclo de vida del Certificado más arriba), vínculo que hoy no existe.
- **Renegociación por salto brusco del dólar (+15%)**: si la cotización de referencia sube un 15% o más respecto al valor vigente al momento de presentar el presupuesto, el sistema debería ofrecer la opción de renegociar el precio de lo que resta ejecutar de la obra — mismo espíritu que la redeterminación por CAC (ver punto anterior), pero disparado por variación del dólar en vez del índice CAC mensual, y aplicado también solo sobre el saldo no certificado. El objetivo es que ninguna de las partes (profesional/constructor o cliente) se vea perjudicada por variaciones externas fuertes. Idealmente debería quedar reflejado en el contrato entre las partes, aunque se reconoce que no siempre hay contrato formal.
- **Período de validez del presupuesto**: al presentar un presupuesto a cliente/profesional, debe incluir un campo "Válido por X días" (con un default sugerido, editable), con fecha de vencimiento calculada automáticamente y reflejada en la exportación PDF. Si el presupuesto vence sin haber sido aceptado, mostrar un aviso visual en el Dashboard (ej. chip "Vencido"). Se relaciona con el punto de CAC de arriba: la redeterminación por CAC solo tiene sentido si el presupuesto venció antes de ser aceptado.

## Commands

```
flutter pub get              # install dependencies
flutter run --dart-define-from-file=env.json   # run with Supabase credentials (see below)
flutter analyze              # static analysis (uses analysis_options.yaml -> flutter_lints)
flutter test                 # run all tests
flutter test test/widget_test.dart   # run a single test file
flutter test test/core/utils/parser_numero_ar_test.dart   # unit tests, no widget/Supabase setup needed
```

**Supabase credentials**: `lib/main.dart` calls `Supabase.initialize()` reading `SUPABASE_URL`/`SUPABASE_ANON_KEY` via `String.fromEnvironment` — a plain `flutter run` (no `--dart-define-from-file`) will initialize with empty values and fail. Copy `env.example.json` to `env.json` (gitignored, never commit it) at the repo root, fill in the real values from the Supabase dashboard (Project Settings → API), and always run/build with `--dart-define-from-file=env.json`.

Two tests exist. `test/widget_test.dart` is a smoke test that pumps `MiAppApu` and checks a `MaterialApp` is found — needs the Supabase/shared_preferences mocking boilerplate at the top of that file because the app boots through `AuthGate`. `test/core/utils/parser_numero_ar_test.dart` (2026-09-01) is the first **pure unit test** in the project — no widget pump, no mocking, just `ParserNumeroAr.parsear` against a table of input strings. It exists because that function decides how a number typed by hand (Argentine convention: comma decimal, dot thousands, max 2 decimals — see `lib/core/utils/parser_numero_ar.dart`'s doc comment for the exact rule) gets interpreted before being saved as money or a quantity in four different screens at once; a wrong interpretation there corrupts data silently, which is exactly what a table-driven test catches cheaply. Run it on its own with the command above — it's instant, no device/emulator needed. No test infrastructure beyond this (still no mocks-for-Supabase-repositories pattern, no golden tests) exists yet.

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
    segurity/    # UserContext permission model, built from ObraMember (note: "segurity" typo, not "security")
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

### Permission model (Etapa 3 complete end-to-end at the data/DB layer — RLS included — first UI wiring live in `PresupuestosScreen`)

Four Supabase tables now back this, per `docs/etapa3_roles_permisos_diseno_datos.md` (migrations `supabase/migrations/000{1,2,3}_*.sql`, all applied in production): `obra_members` (roles combinables per obra+usuario, one row per role — `data/models/obra_member.dart`: `RolProyecto`, `ObraMember`, `PermisosEspeciales`), `modificaciones_obra` + `audit_log` (Adicionales/Demasías/Quitas with a generic append-only audit trail — `data/models/modificacion_obra.dart`, `data/models/audit_log_entry.dart`), and `libro_entradas` (the 3 Gestión de Obra "libros" as one table with a `libro` discriminator — `data/models/libro_entrada.dart`).

`core/segurity/user_context.dart`'s `UserContext` no longer wraps a single global `UserRole` — it's built via `UserContext.desdeObraMembers(...)` from a user's `ObraMember` rows for one obra, and its visibility getters (`puedeVerMontosYAPU`, `esVistaOperativa`, `puedeAprobarCertificados`) are recomputed across however many roles that user combines in that obra (see `RolProyecto` in `obra_member.dart` — it replaced the old standalone `UserRole` enum). `data/models/obra_model.dart` separately still defines `CapaVisibilidad` and `PermisosModulo` (per-obra granular permissions: `verComputo`, `verPreciosFinales`, `verApuYCoeficienteK`, `cargarAvanceFisico`, `editarComputo`, `aprobarCertificados`, `invitarTerceros`) — per the Etapa 3 design doc §1, these are now considered obsolete as a source of truth for real access control (a single flag per obra can't express APU privacy that depends on *who generated* a given record) and should not be extended further; `UserContext`/`obra_members` is the intended mechanism going forward.

**RLS applied in production** (`supabase/migrations/0004_rls_etapa3.sql`, confirmed active in the Supabase dashboard under Database → Policies): all 4 tables now enforce row-level access control at the database layer, built on 3 `SECURITY DEFINER` helper functions (`is_obra_member`, `tiene_rol_en_obra`, `puede_aprobar_monto`) rather than the single-owner pattern `obras` uses (`id_admin_creador = auth.uid()`), since these tables have multiple combinable roles per obra. This means unauthorized reads/writes are now blocked by Postgres itself, independent of the Flutter UI. What RLS does *not* do: column-level redaction — a role like Constructor ("vista operativa, sin montos") can still receive `monto_total`/`tope_monto_aprobacion` in any row it's allowed to read at all, since RLS filters rows, not columns. That's left to the app layer via `UserContext`'s getters.

**First screen wired, verified end-to-end in production (2026-08-19).** `PresupuestosScreen` now builds a real `UserContext` on open: `lib/services/obra_members_repository.dart` (`ObraMembersRepository.getMiembrosDeObra`, new — mirrors `ObrasRepository`'s pattern but hand-maps `obra_members`'s flat snake_case columns to `ObraMember`/`PermisosEspeciales`, since `ObraMember.fromMap` expects the app's own serialized shape, not the raw DB row) plus `AuthService.usuarioActual` feed `UserContext.desdeObraMembers` in `_cargarUserContext()`, called from `initState` once `obraId` is extracted from `widget.obra`. The only visible effect so far: `_buildTabApu()` (tab "2. APU") shows a "sin acceso" placeholder while loading or when `puedeVerMontosYAPU != true`, and only renders the (still mock) APU content when `true` — fail-closed by default (no user, no obraId, or in-flight query all resolve to the placeholder). Confirmed manually against production data both ways: no `obra_members` row for the user on that obra → placeholder; one `admin_maestro` row inserted → full APU content. Every other screen (`ObrasListScreen`, the other 5 tabs of `PresupuestosScreen`, `gestion_obra_tab.dart`, the tabs with the still-unconnected int `obraId`) still shows everything unconditionally — wiring them the same way is the pending work, not a gap in the mechanism itself.

### Modelos de Certificación A/B (Avance Medido / Hitos de Precio Cerrado) — completo a nivel de datos

Pieza nueva sobre Etapa 3, no una extensión de ella. Diseño completo en
`docs/modelos_certificacion_diseno_datos.md`. Aplicada de punta a punta en producción (confirmado
por el usuario en Table Editor / Database → Policies / Database → Functions), 4 migraciones:

- **`0005_modelo_certificacion.sql`**: agrega `obras.modelo_certificacion`
  (`'avance_medido'` | `'hitos_precio_cerrado'`, default `'avance_medido'`) y la función
  `cambiar_modelo_certificacion(obra_id, modelo_nuevo, motivo)` — `update` + `insert` en
  `audit_log` atómico, motivo obligatorio validado en la función misma. No se creó una tabla de
  historial dedicada: reusa `audit_log` (`entidad='obra'`, `entidad_id` null porque `obra_id` ya
  identifica la obra), tal como ese comentario en `audit_log_entry.dart` ya anticipaba. Limitación
  conocida: quién puede ejecutar el cambio depende de la política `UPDATE` que `obras` ya tenía
  antes de Etapa 3 (`id_admin_creador = auth.uid()`, dueño único), no de una verificación
  explícita del rol `admin_maestro` de `obra_members` — pueden divergir si el Administrador de una
  obra fue reasignado después de creada.
- **`0006_hitos_certificacion.sql`** + **`0007_hitos_certificacion_solo_admin.sql`**: tabla nueva
  `hitos_certificacion` para Modelo B — hitos definidos libremente por tiempo o alcance, estado
  `activo`/`finalizado`/`rescindido` (check constraint exige `motivo_rescision` si se rescinde),
  `hito_anterior_id` autorreferenciado igual que `libro_entradas.entrada_padre_id` para modelar que
  un hito rescindido se retoma con otro (posiblemente otro contratista/monto). Doble función de la
  misma tabla: `contratista_nombre` null modela el contrato principal de la obra (el contratista ya
  es el Constructor, con fila en `obra_members`); con valor modela Subcontratos con terceros sin
  cuenta en el sistema. Agrega también `obras.monto_total_contratado`, deliberadamente separada de
  `ObraModel.montoTotal` (bajo Modelo A el total es/debería ser un cálculo derivado del cómputo
  métrico; bajo Modelo B es un input directo del Administrador), y la función
  `calcular_avance_hitos(obra_id)` — el `%` de avance nunca es un campo editable a mano, se calcula
  sumando el `monto` de los hitos `finalizado`, filtrando `contratista_nombre is null` para no
  mezclar el avance certificado al Cliente con pagos a Subcontratistas. RLS incluida desde la
  creación de la tabla (a diferencia de Etapa 3, que la agregó recién como paso final consolidado
  en `0004`): `SELECT` abierto a `is_obra_member`, `INSERT`/`UPDATE` (solo mientras
  `estado='activo'`, lo que congela `finalizado`/`rescindido` de hecho) restringido a
  `admin_maestro` únicamente — `0007` corrigió una primera versión de `0006` que también incluía a
  `profesional`. Sin política `DELETE` (append-only, mismo criterio que el resto de Etapa 3).
- **`0008_ajuste_contrato.sql`**: `modificaciones_obra` (tabla de Etapa 3) gana un cuarto valor de
  `tipo`, `'ajuste_contrato'` (check constraint fuerza `subitem_id`/`apu_privado_id` nulos y
  `cantidad = monto_total`, ya que es un ajuste puramente monetario sin cómputo métrico de por
  medio), y la función `aprobar_ajuste_contrato(modificacion_id, comentario)` — aprueba + aplica el
  delta a `obras.monto_total_contratado` + registra `audit_log`, atómico, reusando
  `puede_aprobar_monto` (de `0004_rls_etapa3.sql`) como cadena de autoridad. Motivación: un aumento
  de `monto_total_contratado` después de su carga inicial es plata que termina pagando el Cliente,
  mismo peso que un Adicional — no puede ser edición libre del Administrador, tiene que pasar por
  el mismo circuito de aprobación que ya usa `modificaciones_obra`. La carga *inicial* de
  `monto_total_contratado` (primera vez, de `null` a un número) sigue siendo edición directa
  simple, sin pasar por acá.

**Deuda técnica aceptada explícitamente por el usuario** (no un descuido — documentada inline en
`0008_ajuste_contrato.sql`, y el usuario decidió no cerrarla ahora): (a) la política
`modificaciones_obra_update` genérica todavía permite aprobar un `ajuste_contrato` con un `UPDATE`
directo sin pasar por `aprobar_ajuste_contrato()`, dejando la modificación aprobada sin aplicar el
delta ni generar su `audit_log` específico si alguien evita la función; (b) nada a nivel de base
impide editar `obras.monto_total_contratado` directamente aunque ya tenga un valor cargado — la
regla "editable libre solo en la carga inicial" es convención de la capa de app, no forzada en la
base. Ambas se dejaron sin trigger a propósito, por consistencia con cómo ya funciona la graduación
de un `adicional` a Subitem real (tampoco forzada a nivel de base, es efecto de app) — el usuario
aceptó el riesgo porque hoy es el único que toca la base directamente y el código Dart va a llamar
siempre a la función. Revisar si en algún momento se suma otro desarrollador con acceso directo a
la base.

**No implementado en esta pieza puntual** (fuera de su alcance desde el diseño, no un olvido):
ninguna conexión a Dart/UI de lo de acá — `data/models/hito_certificacion.dart` quedó propuesto en
el diseño pero no se creó, `gestion_obra_tab.dart` no toca nada de esto. **Actualización posterior**:
el ciclo completo de 5 estados del certificado de Modelo A, que en su momento quedaba fuera de
alcance ("ver 'Ciclo de vida del Certificado de Obra' más abajo"), ya se implementó como pieza
aparte — ver la sección siguiente. Las columnas `anticipo_pct`/`fondo_reparo_pct` (diseñadas acá,
§6, sin dependencia dura en su momento) terminaron migrándose como parte de esa pieza siguiente, no
de esta.

### Ciclo de vida del Certificado de Obra (5 estados, Modelo A) — capa de datos completa

Pieza nueva sobre Modelos de Certificación A/B (la sección de arriba) y sobre Etapa 3. Diseño
completo en `docs/certificados_ciclo_vida_diseno_datos.md`. Aplicada de punta a punta en producción
(confirmado por el usuario en Table Editor / Database → Policies / Database → Functions), 4
migraciones:

- **`0009_certificados.sql`**: agrega `obras.dias_plazo_pago_certificados`/`anticipo_pct`/`fondo_reparo_pct`
  (estas dos últimas ya estaban diseñadas en la pieza de Modelos A/B, §6, pero se habían dejado sin
  migrar hasta que fueron dependencia dura de un certificado real), la tabla `certificados` con los 5
  estados (`borrador`/`emitido`/`leido`/`pagado`/`impactado_cerrado`, con `check` de coherencia de
  fechas por estado), el helper `obra_modelo_es(obra_id, modelo)` (adelantado desde el paso 2 porque
  la política `INSERT` ya lo necesitaba), y RLS completa desde el mismo archivo — `SELECT` abierto a
  `is_obra_member`, `INSERT` para `admin_maestro`/`profesional`/`constructor` con guard de "solo
  Modelo A" (`certificados` no aplica bajo Modelo B, que usa `hitos_certificacion`).
- **`0010_certificados_update_solo_borrador.sql`**: corrección sobre `0009` — la política `UPDATE`
  original dejaba que cualquier usuario logueado con uno de 5 roles hiciera un `UPDATE` directo sobre
  un certificado ya emitido, sin pasar por ninguna función (riesgo real desde el uso normal de la
  app, a diferencia del límite ya aceptado para `ajuste_contrato`, donde el usuario es el único con
  acceso directo a la base). Corregida: `UPDATE` directo solo permitido mientras
  `estado = 'borrador'`, con `admin_maestro`/`profesional`/`constructor`; cualquier cambio de estado
  por fuera de eso queda bloqueado a nivel de política.
- **`0011_certificados_funciones_transicion.sql`**: por la restricción de `0010`, las funciones de
  transición no pueden ser `SECURITY INVOKER` como `cambiar_modelo_certificacion`/`aprobar_ajuste_contrato`
  — son `SECURITY DEFINER`, con el chequeo de autoridad hecho a mano en el cuerpo de cada una.
  Agrega el helper `puede_gestionar_certificado(obra_id, monto)` (variante de `puede_aprobar_monto`
  sin el acceso incondicional de `admin_maestro`/`profesional`, porque quien lee/paga un certificado
  es específicamente el Cliente o su Apoderado, no la Empresa) y 5 funciones: `emitir_certificado`
  (Borrador→Emitido, `admin_maestro`/`profesional`, calcula y snapshotea anticipo/fondo de reparo,
  bloquea si el certificado anterior requería firma física y no se subió el PDF firmado),
  `marcar_certificado_leido` (Emitido→Leído, `cliente_principal`/`invitado_apoderado`, idempotente —
  pensada para que la app la llame automáticamente al abrir el detalle, no por botón),
  `marcar_certificado_pagado` (Emitido o Leído→Pagado — "Leído" es salteable, completa `fecha_lectura`
  como efecto colateral si hacía falta —, `puede_gestionar_certificado`), `marcar_certificado_impactado`
  (Pagado→Impactado y Cerrado, `admin_maestro`/`constructor`, no `profesional` — son responsabilidades
  distintas: quien emite vs. quien cobra y cierra administrativamente), y una 5ª función no contada
  en el diseño original, `subir_pdf_firmado_certificado` (independiente del estado del ciclo,
  `admin_maestro`/`profesional`) — sin ella el bloqueo de firma física de `emitir_certificado` sería
  imposible de destrabar nunca, dado que `0010` ya no deja ningún `UPDATE` directo sobre un
  certificado emitido.
- **`0012_hitos_certificacion_guard_modelo.sql`**: cierra un gap retroactivo encontrado al diseñar
  esta pieza — `hitos_certificacion` (Modelo B, ya en producción desde antes) nunca chequeó
  `obras.modelo_certificacion`, así que se podía crear/editar un hito de contrato principal aunque la
  obra estuviera en Modelo A. Corregido con el mismo `obra_modelo_es()` de `0009`, condicionado a
  `contratista_nombre is null` (el guard no aplica a los Subcontratos que esa misma tabla también
  aloja, que no dependen del modelo de certificación de la obra) — en `INSERT` y también en `UPDATE`.

**Paso 1 de conexión a UI: verificado en producción (2026-08-21)**, ver detalle arriba en
"Verificación de implementación" — `gestion_obra_tab.dart` lee la tabla `certificados` real, solo
lectura, conectado a `PresupuestosScreen` pestaña 5 ("Gestión de Obra").

**No implementado todavía**: ninguna de las 5 funciones de transición conectada desde Dart (la UI no
tiene ningún botón de escritura por ahora — deliberado, ver arriba); la matriz de permisos por tipo
de relación cliente-obra (Cliente Autoconstructor / con Profesional+Contratista / con Contratista
Directo) sigue sin ningún soporte de datos, es una capa de visibilidad aparte que no cambia el
schema de `certificados`; y la generación real de PDF (paquetes `pdf`/`printing` siguen sin usarse en
todo `lib/`) — el "PDF firmado" de acá es solo un adjunto (`text[]` de URLs) que alguien sube desde
afuera, no algo que la app genere.

### RLS del bloque proveedores/insumos/precios — pieza cerrada

Pendiente de seguridad detectado en auditoría: 6 tablas del dominio "proveedores" (creadas fuera
del flujo de migraciones, en una sesión de Gemini para otro propósito, sin relación con el resto
del schema versionado en `supabase/migrations/`) tenían **RLS deshabilitado en producción** —
cualquiera con la anon key podía leer/editar/borrar todo. Diagnóstico completo hecho en
conversación (no hay doc en `docs/` para esta pieza): de las 6, solo 3 tenían datos reales y
formaban un flujo conectado — `insumos` (12 filas) ↔ `precios` (60 filas, `insumo_id`+`corralon_id`)
↔ `corralones` (8 filas, con `lat`/`lng` ya cargados). Las otras 3 — `proveedores` (1 fila de
prueba), `insumos_proveedor` y `documentos_proveedor` (0 filas) — no tienen ninguna FK hacia/desde
ese flujo real; probablemente un segundo intento de modelado que nunca se conectó al que quedó en
uso. `calcular_precio_promedio_insumo()`, referenciada más arriba en este archivo como parte del
motor de proveedores, no existía — era un nombre de función documentado como plan, nunca
implementada (confirmado probando el RPC contra Supabase con varias firmas: `PGRST202`, ningún
match en el schema cache).

Resuelto en **`0013_rls_proveedores_precios.sql`**, aplicada y verificada en producción
(2026-08-22, confirmado por el usuario en Database → Functions y Table Editor → Policies):

- `corralones` suma columna `usuario_id uuid references auth.users(id)` (nullable — las 8 filas de
  seed quedan sin dueño, congeladas para edición hasta asignación manual, comportamiento esperado).
  RLS: `SELECT` abierto a cualquier autenticado (directorio nombre/ciudad/ubicación, sin precios,
  para que un profesional elija a quién pedir presupuesto), `UPDATE` solo el dueño
  (`usuario_id = auth.uid()` en `using` y `with check` — verificado que esto ya bloquea reasignar
  el dueño en el mismo `UPDATE`, sin necesitar referencia a `OLD`, porque ambas cláusulas quedan
  ancladas al mismo `auth.uid()`). Sin política `INSERT`/`DELETE` — no hay pantalla de alta de
  corralón en la app todavía, alta sigue siendo manual vía SQL Editor.
- `precios` (la tabla sensible real — cuánto cobra cada corralón por insumo): `SELECT`/`INSERT`/
  `UPDATE` restringidos al dueño del corralón vía el helper `is_corralon_owner(corralon_id)`
  (`SECURITY DEFINER`, mismo patrón que `is_obra_member` de `0004_rls_etapa3.sql`). Ni un
  arquitecto autenticado puede hacer `SELECT` crudo. Sin `DELETE` — append-only, mismo criterio
  que `libro_entradas`/`audit_log`.
- `calcular_precio_promedio_insumo(p_insumo_id)`: ahora sí existe, `SECURITY DEFINER`, devuelve
  `promedio, minimo, maximo, cantidad_corralones` (agregados únicamente, nunca `corralon_id` ni
  `valor` fila por fila) — única vía legítima para que alguien fuera del dueño del corralón sepa
  algo sobre precios. Promedio simple de todo lo que haya en `precios` para ese insumo, **sin**
  filtro de radio geográfico ni fallback a MercadoLibre (eso es roadmap del motor de precios
  completo, documentado aparte, fuera de alcance de esta pieza).
- `insumos`: `SELECT` abierto a cualquier autenticado, sin política de escritura — en este proyecto
  "admin" siempre significa `admin_maestro` (rol por obra), no existe un concepto de administrador
  global de la plataforma e `insumos` no pertenece a ninguna obra, así que la escritura queda
  exclusivamente a mano vía SQL Editor hasta que ese concepto se diseñe, si hace falta.
- `proveedores`/`insumos_proveedor`/`documentos_proveedor`: RLS habilitada sin ninguna política →
  bloqueo total (solo `service_role` ve algo). Sin diseño elaborado a propósito, porque están
  vacías/desconectadas y puede que ni se terminen usando.

**No implementado en esta pieza** (fuera de alcance desde el diseño, no un olvido): ninguna
conexión a Dart/UI — grep sobre `lib/` no encontró ningún archivo que toque estas 6 tablas ni la
función de promedio, así que este cierre de seguridad no rompe nada existente. El motor de precios
completo (filtro de radio ~200km, fallback MercadoLibre, banda de precio con fuente/fecha) y los
niveles de membresía paga por corralón siguen siendo roadmap sin construir — se dejó preparado el
terreno donde no costaba nada (`lat`/`lng` ya estaban, el retorno de la función ya trae
mínimo/máximo/cantidad para la futura banda de precio) pero sin anticipar columnas o mecanismos
cuyo diseño final todavía no está cerrado (ej. columna de nivel de membresía, deliberadamente no
agregada todavía).

### Rubros / APU (Solapa 1 y 2): diseño de datos cerrado, sin implementar (2026-08-22)

Pieza previa al Importador de Excel/PDF (ver más abajo) — se confirmó en conversación que Rubros/
APU necesitan persistencia real en Supabase antes de que el Importador tenga a dónde mapear datos,
y antes de poder cerrar el catálogo Freemium/PRO ya definido conceptualmente. Diseño completo en
`docs/rubros_apu_diseno_datos.md`, **cerrado y aprobado pero sin ninguna migración escrita ni
aplicada todavía** — a diferencia de las secciones anteriores de este archivo, esto no es estado de
producción.

**Diagnóstico confirmado**: `Rubro`/`Subitem`/`SubitemBase`/`Insumo`/`InsumoApu`/`ComponenteApu`
(`data/models/`) son modelos Dart en memoria pura, sin ningún repository ni tabla de Supabase.
`RubrosTab` está conectada a `PresupuestosScreen` pero se instancia sin pasar `rubros:` → arranca
vacía en cada apertura, sin persistencia entre sesiones. `AnalisisPreciosTab` (candidato a Solapa 2)
existe como archivo pero no está wireada — la pestaña "2. APU" sigue siendo el `_buildTabApu()`
mock inline. Ninguna de las 13 migraciones aplicadas crea `rubros`/`subitems`/tabla de APU.

**8 decisiones de diseño cerradas** (detalle completo en el doc, §3):
- Catálogo de insumos para APU: **reusa la tabla `insumos` ya existente** (proveedores/precios, no
  se crea una tabla nueva) — para que un insumo de APU sea el mismo que se cotiza contra corralones
  vía `calcular_precio_promedio_insumo()`. Probablemente necesita `alter table` (columna `tipo`
  material/mano_obra/equipo, `porcentaje_cargas_sociales`, `creador_usuario_id` nullable) — pendiente
  verificar contra el schema real de producción.
- Precio de un subítem: vivo mientras la obra está en presupuesto, se congela al emitir un
  certificado (reusa el mecanismo de snapshot que ya tiene `emitir_certificado()`, no uno nuevo).
- Un subítem puede repetirse en la misma obra (campo `sector` opcional en `obra_subitems`).
- `macrorrubro` pasa a ser tabla fija (`macrorrubros`, ~17 valores) — **bloqueante real**: el
  listado concreto todavía no lo tiene el usuario, no se puede sembrar la tabla sin él.
- Personalización PRO de un subítem/APU: **de la persona (`creador_usuario_id`), no de la obra** —
  mismo criterio que Etapa 3 ya cerró para ownership de APU. Reusable en todas las obras del dueño;
  la visibilidad de un colaborador con `puede_ver_apu_ajena` sigue acotada por obra (política de RLS
  exacta en el doc §2.6).
- Free/PRO en la escritura del catálogo: queda en capa de app por ahora, marcado explícitamente
  como **deuda técnica real de monetización** (no una convención cerrada) — no hay tabla de
  plan/suscripción todavía de la cual colgar el control a nivel de RLS.
- `sistema_constructivo`: relación muchos-a-muchos (`rubro_sistema_constructivo`), no columna única
  — un rubro puede aplicar a varios sistemas constructivos a la vez.
- Excel de 2 pestañas que el usuario está preparando (rendimientos reales): pendiente, sin resolver
  hasta tenerlo — cuando esté listo, mapear columna→campo contra el archivo real.

**Orden de implementación propuesto** (7 pasos, ninguno ejecutado): (0) introspectar schema real de
`insumos` en producción; (A) `macrorrubros`+`sistemas_constructivos`+`rubros`+
`rubro_sistema_constructivo`, bloqueada por el listado semille pendiente; (B) `subitems`; (C)
`alter table insumos`; (D) `apu_composiciones`+`apu_composicion_items` (la política de RLS más
delicada de la pieza); (E) `obra_subitems`; (F) cierre de las FKs pendientes de
`modificaciones_obra.subitem_id`/`apu_privado_id` que quedaron sueltas desde Etapa 3. Ver
`docs/rubros_apu_diseno_datos.md` §4 para el detalle completo.

**Actualización 2026-08-28 — ver sección siguiente**: el bloqueante de macrorrubros de este párrafo
quedó **resuelto y reemplazado** por la parte 2 del diseño (`docs/rubros_apu_permisos_selector_diseno_datos.md`),
que trae el listado real de 19 rubros y descarta `macrorrubros`/`sistemas_constructivos` del
schema. No se toca este párrafo por lo demás, queda como registro histórico de cómo se llegó ahí.

### Rubros / APU, parte 2: permisos Free/PRO, selector, listado real de 20 rubros — APLICADA EN PRODUCCIÓN (2026-08-28)

Extiende la pieza anterior — **las 9 ambigüedades de negocio resueltas y las 8 migraciones
aplicadas y verificadas en producción por el usuario, de punta a punta.** Capa de negocio de
`docs/computopro_rubros_apu_spec.md`, verificada contra el archivo real
`docs/seed/PLANILLA_BASE_2_0_v3_CORREGIDA.ods`. Diseño completo en
`docs/rubros_apu_permisos_selector_diseno_datos.md`.

**Cerrado a nivel de schema/base de datos. Dos cosas quedan explícitamente fuera de esta pieza, no
son un olvido:**
1. **Carga de composiciones reales de APU** (materiales/rendimientos de Steel Frame, Balloon
   Frame, Metálicas Livianas, etc.) — tarea de curación del usuario, requiere expandir el
   catálogo de `insumos` primero y limpiar a mano los nombres con caracteres corruptos del
   archivo original. `apu_composiciones`/`apu_composicion_items` quedaron creadas vacías a
   propósito (Migración 5, `0018_apu_composiciones.sql`).
2. **Conexión a Dart/UI**: primer paso ya hecho y verificado por el usuario en el teléfono
   (2026-08-28) — ver "Conexión a Dart/UI: catálogo de rubros y subitems" más abajo.
   `AnalisisPreciosTab` sigue sin tocar, y dentro de Rubros todavía falta subitems/apu/obra_subitems.

**Migraciones aplicadas** (`supabase/migrations/0014` a `0021`, todas confirmadas por el usuario
en Table Editor / Database → Policies / Database → Functions):
- `0014_perfiles.sql`: tabla `perfiles` (`usuario_id` → `auth.users`, `es_pro boolean default
  false`) — primer paso, deliberadamente chico, de la pieza más grande "Sistema de Registro/Login
  de Usuarios" que este archivo ya tenía pendiente sin diseñar. Trigger `AFTER INSERT on
  auth.users` + backfill. **RLS solo `SELECT`** — sin `UPDATE`/`INSERT` para el usuario mismo:
  con `UPDATE using(usuario_id = auth.uid())` (el patrón que usa el resto del proyecto para
  tablas de dueño) cualquier Free podría auto-otorgarse `es_pro = true` llamando directo a la API
  de Supabase. `es_pro` cambia solo a mano vía SQL Editor hasta que haya un sistema de pagos real.
- `0015_rubros.sql`: tabla `rubros` (`usa_apu boolean`, `tipo_precio_manual` `'unitario'|'global'`
  con `check` de coherencia) sembrada con los 20 rubros reales — ver listado más abajo.
- `0016_subitems.sql`: tabla `subitems`, sembrada con 116 subitems reales (excluye las filas
  "OTRO" de cada rubro, esas van por `obra_subitems.descripcion_libre`). Un bug real en la
  extracción automática se comía los 10 subitems de Rubro 1 en el primer intento — detectado y
  corregido antes de aplicar, no llegó a producción.
- `0017_alter_insumos.sql`: agrega `tipo`/`unidad_compra`/`factor_conversion`/
  `porcentaje_cargas_sociales`/`creador_usuario_id` a `insumos` (backfill `tipo='material'` para
  las 12 filas ya existentes, confirmado en vivo), siembra los 5 insumos oficiales de mano de obra
  (Oficial Especializado/Oficial/Medio Oficial/Ayudante/Ayuda de Gremio, `porcentaje_cargas_sociales`
  en `NULL` — la escala UOCRA queda pendiente de que el usuario la tenga actualizada). RLS
  extendida con `INSERT`/`UPDATE`/`DELETE` por dueño, mismo patrón que `rubros`/`subitems`.
- `0018_apu_composiciones.sql`: tablas `apu_composiciones` + `apu_composicion_items`, **solo
  schema, sin ninguna composición sembrada** (ver punto 1 de arriba). Corrigió una imprecisión
  real del diseño original: un `unique(subitem_id, creador_usuario_id)` sin más no alcanza para
  garantizar "una sola receta oficial por subítem" en Postgres (dos `NULL` nunca son iguales entre
  sí en una constraint `unique`) — se agregó el índice único parcial que sí lo cierra. Agrega
  también las funciones `is_apu_composicion_owner`/`puede_ver_apu_composicion` (`SECURITY
  DEFINER`), necesarias porque `apu_composicion_items` no tiene dueño propio, lo hereda vía join.
- `0019_obra_subitems.sql`: tabla `obra_subitems` (`rubro_id` explícito, `subitem_id` nullable
  para la fila OTRO, `precio_unitario_manual`) — el cómputo métrico real de una obra. De paso
  cierra la limitación que venían arrastrando `rubros`/`subitems`/`apu_composiciones`: ahora que
  existe una tabla real de "qué está tildado en qué obra", se extendieron esas 3 políticas de
  `SELECT` (vía `ALTER POLICY`, no `DROP`/`CREATE`) para que un colaborador con
  `puede_ver_apu_ajena` vea la personalización del dueño acotada a lo tildado en su obra, tal como
  preveía el diseño desde el arranque.
- `0020_obra_presupuesto_config.sql`: tabla `obra_presupuesto_config` (1:1 con `obras` — selector
  de tipo de presupuesto, con/sin impuestos, suelo, zona sismorresistente, y los % del resumen
  APU) + `obra_impuestos` (4 filas fijas por obra: IVA/IIBB/Tasas Municipales/Otro, con `check` de
  coherencia). Trigger `AFTER INSERT on obras` + backfill para las obras ya existentes. Corrigió
  otra imprecisión real: el `check` original exigía `nombre_otro` obligatorio en la fila `'otro'`,
  lo que habría roto el propio `insert` del trigger en cada obra nueva (esa fila se siembra vacía
  a propósito) — se invirtió la regla a "nombre_otro nunca se usa fuera de la fila 'otro'".
- `0021_modificaciones_obra_fks.sql`: cierra las FKs de `modificaciones_obra.subitem_id`/
  `apu_privado_id` que quedaban sueltas desde Etapa 3 (`0002_modificaciones_obra_audit_log.sql`),
  ahora que `subitems`/`apu_composiciones` existen. Sin errores al aplicar — confirma que ninguna
  fila vieja de `modificaciones_obra` tenía esos campos cargados con un valor huérfano.

**6 definiciones de negocio cerradas esta sesión** (detalle en el doc §1-§2):
- Coeficientes (GG/Imprevistos/EPP/Beneficio/Costo financiero): solo default a nivel de obra
  (`obra_presupuesto_config`, tabla 1:1 nueva), sin override por partida en esta pieza.
- "Gestión de materiales de terceros" (4% default, vista sin materiales): valor único por obra,
  no por partida — misma tabla.
- Impuestos: `obra_impuestos` (tabla nueva por obra) con `tipo` restringido
  (`iva`/`iibb`/`tasas_municipales`/`otro`), no texto libre — evita variantes de string del mismo
  impuesto entre obras. Sembrada con 4 filas default (21%/3%/1.5%/0%) al crear la obra.
- `rubros.usa_apu` (columna nueva, booleana): flag genérico de "rubro sin vínculo a APU, precio
  100% manual" — no hardcodeado a Rubro 1. Confirmado que aplica a 4 rubros (1, 18, 19, 20), con
  dos sub-casos distintos — ver más abajo.
- Fila "OTRO" de cada rubro: reusa `obra_subitems` (`subitem_id` pasa a nullable +
  `descripcion_libre` + `rubro_id` explícito), no una tabla aparte.
- Free/PRO: se suma una tabla nueva mínima `perfiles` (`usuario_id` → `auth.users`, `es_pro
  boolean default false`) — primer paso, deliberadamente chico, de la pieza más grande "Sistema de
  Registro/Login de Usuarios" que este archivo ya tenía pendiente sin diseñar. Aclarado además:
  Free **ya podía** ver la composición completa del APU en modo lectura (el RLS fundacional nunca
  la ocultó, solo la edición está restringida en capa de app) — no era una ambigüedad nueva, era
  una aclaración de algo que el diseño ya permitía.

**Bloqueante de macrorrubros resuelto — reemplazado, no complementado**: el usuario subió el
archivo real de la planilla con la que trabajó una semana. El catálogo de ~17 "macrorrubros" de la
sesión anterior queda **descartado**, no es un nivel jerárquico distinto — la tabla `macrorrubros`
sale del diseño. Los 19 rubros reales, en orden: Tareas Preliminares, Movimientos de Suelos,
Fundaciones, Estructuras de Hormigón Armado, Estructuras de Steel Frame, Estructuras de Balloon
Frame, Estructuras Metálicas Livianas, Mamposterías, Capas Aisladoras, Revoques y Yesería,
Contrapisos y Carpetas, Pisos y Zócalos, Revestimientos Húmedos, Revestimientos Secos, Cubiertas,
Cielorrasos, Pinturas, Instalaciones, Carpinterías, y un **20º rubro confirmado: "VARIOS"**
(subitems Limpieza Periódica de Obra / Limpieza Final de Obra / OTRO) — listado completo con
código/orden en el doc §2.1.

**`sistema_constructivo` se simplifica — `sistemas_constructivos`/`rubro_sistema_constructivo`
salen del diseño.** El archivo real confirma que Hormigón Armado/Steel Frame/Balloon
Frame/Metálicas Livianas ya son los rubros 4 a 7 de primer nivel, no subitems de un rubro
"Estructura" común — no hace falta una relación N:M para modelar qué sistema constructivo usa una
obra, alcanza con qué subitems de esos 4 rubros el usuario carga (pueden coexistir varios, ej.
Fundaciones de Hormigón + Steel Frame arriba). De paso, se confirmó que las partidas de Steel
Frame/Balloon Frame/Metálicas Livianas ya traen composición técnica real cargada en el archivo
(ej. partida 5.1 con insumos y rendimientos puestos, no solo plantilla vacía) — el diseño ya
cerrado de `apu_composicion_items`/`insumos` la absorbe sin cambios.

**Las 3 preguntas quedaron cerradas** (respondidas por el usuario con una captura real de la
planilla, ver doc §1 puntos 7-9):
- Rubro 20 se llama **"VARIOS"**, no un nombre inventado — confirmado con la fila real del `.ods`.
- `usa_apu = false` aplica a **4 rubros con 2 sub-casos**, no solo a Rubro 1: Rubro 1 y Rubro 20
  usan precio **unitario** manual (cantidad × precio unitario, igual que un subítem normal, pero
  tipeado a mano); Rubro 18 (Instalaciones) y Rubro 19 (Carpinterías) usan precio **global**
  manual (un monto único para toda la partida, sin desglose por unidad técnica). Se agregó
  `rubros.tipo_precio_manual` (`'unitario' | 'global'`, con `check` de coherencia con `usa_apu`)
  para distinguirlos — ver doc §2.1.
- Equipos se compone igual que Material/Mano de obra
  (`apu_composicion_items.tipo_componente = 'equipo'`) — **el schema ya lo soportaba sin cambios**
  desde el diseño fundacional, el `check constraint` ya incluía `'equipo'` como valor válido.

**Salvedad de Equipos, cerrada**: el usuario confirmó con una captura real de la partida 19.3 que
la fila "3 — EQUIPOS" del resumen existe pero el monto queda vacío — no es un problema de guardado
del archivo (como se sospechaba), es que ese dato específicamente no está cargado todavía en la
mayoría de las partidas de la planilla real. Confirma la lectura original: `equipo` se compone
igual que material/mano de obra (`apu_composicion_items.tipo_componente = 'equipo'`, sin cambios
de schema, ya estaba soportado), el campo queda vacío/editable para que el usuario lo complete
partida por partida con su propio criterio.

**Para retomar** (cuando se decida seguir con esta pieza): carga de composiciones reales de APU
(curación del usuario, no iniciada) y seguir la conexión a Dart/UI más allá del primer paso — ver
sección siguiente para el estado exacto.

### Vista "sin materiales" — por qué Gastos Generales/EPP/Costo Financiero no se recalculan

Escrito dentro del propio `docs/seed/PLANILLA_BASE_2_0_v3_CORREGIDA.ods`, hoja
`APU_SIN_MATERIALES`, fila 2 — no en ningún `.md` del repo, por eso quedó sin encontrar la primera
vez que hizo falta. Cita textual completa, es todo lo que está escrito sobre este criterio:

> "Gastos Generales, EPP-Seguridad y Costo Financiero se mantienen iguales que en la solapa APU (no
> dependen de quien compra los materiales). Imprevistos y Beneficio se recalculan sobre la base sin
> materiales. Se agrega una linea de Gestion de materiales de terceros (celda amarilla = % editable)."

La planilla lo implementa al pie de la letra, confirmándolo: en esa hoja, `GASTOS GENERALES` es
`=[$APU.G34]-[$APU.G33]` — extrae el monto absoluto ya calculado en la solapa `APU` completa
(Costo-Costo+GG menos Costo-Costo puro), no lo recalcula sobre la base sin materiales. Mismo
tratamiento para EPP-Seguridad y Costo Financiero.

**Lo de arriba es todo lo que está documentado.** Lo que sigue es lectura de quien escribe esto, no
una cita — no está en ningún archivo: GG/EPP/Costo Financiero son gastos de estructura de la
empresa contratista y no dependen de quién compra los materiales; Imprevistos sigue el riesgo de lo
que efectivamente se ejecuta y Beneficio es margen sobre lo que efectivamente se cobra, por eso esos
dos sí se recalculan sobre la base reducida y los otros tres no.

**Consecuencia práctica, decisión vigente con una consecuencia conocida — no un bug ni un
pendiente**: como GG se arrastra de la APU completa (calculado sobre un Costo-Costo que incluye
materiales) pero se muestra en una partida que ya no los tiene, GG puede terminar siendo varias
veces la mano de obra que lo genera. Caso real, partida "Retak 15cm": $12.728 de GG contra $4.734 de
mano de obra. Es coherente con el criterio de arriba, pero es un número que cuesta explicar en un
presupuesto de solo mano de obra. Si se revisa algún día, que quien lo mire sepa que fue así a
propósito.

### Factor K (Solapa APU) — Paso A construido: bloque de cabecera, sin montos

`BloqueFactorK` (`lib/presentation/obra_detalle/tabs/bloque_factor_k.dart`), primer elemento debajo
de `SelectorTipoPresupuesto` en la Solapa APU: los 6 conceptos (7 en "Comp. Solo MO", con Gestión
de materiales de terceros) con su % y su base en texto plano ("Imprevistos — 4% sobre Costo-Costo +
GG"), **sin ningún monto** — no existe un Costo-Costo único de la obra, cada partida tiene el suyo,
y hoy no hay cómputo métrico conectado para agregarlos. Free ve todo, PRO edita en
`PanelEditarFactorK` (gate en el botón "Editar", antes de abrir — no al abrir, a diferencia del
panel de cargas sociales de mano de obra; los dos son consistentes con la misma regla general por
motivos distintos, ver el doc). Plegable con persistencia por obra en `SharedPreferences`, mismo
mecanismo que el aviso de orden de `rubros_tab.dart`. Sin migración — las 6 columnas de
`obra_presupuesto_config` (`0020`) alcanzan.

De paso, se eliminó el ítem mock de la Solapa APU ("02.01 Hormigón armado...", \$320.000 inventado)
— mismo criterio que la barra falsa de Rubros: mostrar cifras que no reflejan nada real es peor que
no mostrarlas. Reemplazado por un estado vacío honesto, sin prometer un camino de carga que hoy no
existe.

Detalle completo de todas las decisiones de esta ronda (por qué sin montos, la base de cada línea,
el tratamiento en modo sin materiales, el gate de PRO, el séptimo campo que no se pisa) en
`docs/factor_k_apu_decisiones.md` — leer ahí, no repetir acá.

**Pendiente — Paso B, sin empezar**: el desglose de 15 líneas con montos reales de una partida
puntual. Necesita cómputo métrico real primero (`obra_subitems` con cantidades — no existe ninguna
fila hoy, nada en `lib/` escribe ahí todavía), después conectar `calcular_precio_apu_subitems`
(`0034`, aplicada pero sin usar) para el Costo-Costo, y una función SQL nueva para la cascada
completa de 6 conceptos — mismo criterio que `calcular_valor_hora_mano_obra`, la cuenta vive en un
solo lugar.

### Conexión a Dart/UI: catálogo de rubros y subitems — verificado en producción (2026-08-28)

Conexión real de Rubros/APU parte 2 a `lib/`, en pasos chicos y verificables, mismo criterio que se
usó para conectar certificados. Dos pasos hechos hasta ahora, ambos **solo lectura**, sin tocar
`apu_composiciones`/`obra_subitems` todavía:

**Paso 1 — catálogo de rubros.** Solapa 1 lee los 20 rubros reales desde Supabase. Verificado por
el usuario en el teléfono: orden correcto, "Precio manual (unitario)" visible en Tareas
Preliminares.

**Paso 2 — subitems por rubro.** Tocar un rubro en la lista abre una pantalla nueva con sus
subitems reales de Supabase (antes no reaccionaba al tap, esperado en el paso 1). Verificado por el
usuario en el teléfono con un rubro de más de 9 subitems (para confirmar el orden natural, ver
abajo).

**Diagnóstico confirmado antes de tocar código** (no había cambiado nada del "Paso 0" original):
`RubrosTab` (`presupuestos_screen.dart:164`) se instanciaba como `RubrosTab(obra: obraModelParaTab)`
sin pasar `rubros:`, así que `_listaRubros` arrancaba siempre vacía — confirmado, no asumido.
`Rubro`/`Subitem` (`data/models/`) seguían siendo los modelos en memoria pura de siempre, sin
relación con el schema real (sin `orden`/`usa_apu`/`tipo_precio_manual`, `Subitem` todavía mezcla
catálogo con instancia de obra).

**Qué se agregó**:
- `lib/data/models/rubro_catalogo.dart` (`RubroCatalogo`) — fila de catálogo real (`id`, `codigo`,
  `nombre`, `orden`, `usaApu`, `tipoPrecioManual`, `creadorUsuarioId`). Deliberadamente separado de
  `Rubro` (que sigue existiendo tal cual, sin tocar, para el flujo de edición en memoria — son
  conceptos distintos: fila de catálogo vs. instancia editable con subitems).
- `lib/services/rubros_repository.dart` (`RubrosRepository.getCatalogoOficial()`) — mismo patrón
  manual snake_case↔camelCase que `CertificadosRepository`/`ObraMembersRepository`. Sin parámetro
  de obra: `rubros` es catálogo global, no depende de `obraId` (a diferencia de certificados).
- `rubros_tab.dart` reescrito: 3 estados (`_cargando`/`_error`/lista) mismo patrón que
  `gestion_obra_tab.dart`. **Se sacaron el FAB "Nuevo Rubro" y los íconos de editar/eliminar** (no
  solo deshabilitados, eliminados) junto con los métodos que mutaban `_listaRubros` en memoria y la
  barra "SUBTOTAL CÓMPUTO DIRECTO $0 · 0 Rubros" — mismo criterio ya aplicado en
  `gestion_obra_tab.dart`: mostrar acciones/cifras que no reflejan nada real es peor que no
  mostrarlas, y acá era más grave todavía por mezclar esa barra falsa con una lista de 20 rubros
  reales debajo. Vuelven cuando se diseñe el alta real vía Supabase (custom PRO).

**Bug real encontrado y corregido, no específico de esta pieza**: `postgrest-dart` (el cliente que
usa `supabase_flutter`, confirmado en el paquete instalado, versión 2.9.1) tiene `.order()` con
`ascending` en default **`false`** (descendente) — al revés de SQL y de `postgrest-js`, documentado
así en el propio paquete. `rubros_repository.dart` lo pisaba sin darse cuenta (`.order('orden')`
sin `ascending: true` → catálogo salía 20→1 en el teléfono). Revisados los 3 `.order()` que existen
hoy en todo `lib/`:
- `rubros_repository.dart` (`orden`) → corregido a `ascending: true` (bug real).
- `certificados_repository.dart` (`numero`) → mismo bug latente, corregido también aunque no se
  había notado todavía (ningún usuario con varios certificados fuera de orden hasta ahora).
- `obras_repository.dart` (`created_at`, dashboard principal) → **no es el mismo bug**: el
  resultado actual (obras más nuevas primero) es el orden esperado para un dashboard de proyectos,
  no un accidente. Se dejó `ascending: false` explícito con comentario aclarando que es intencional,
  para que no se confunda con los otros dos casos si alguien lo revisa después.

**Qué se agregó en el paso 2**:
- `lib/data/models/subitem_catalogo.dart` (`SubitemCatalogo`) — mismo criterio que
  `RubroCatalogo`, fila de catálogo sin cantidad/precio (viven en `obra_subitems`, pieza siguiente).
- `lib/services/subitems_repository.dart` (`SubitemsRepository.getSubitemsDeRubro(rubroId)`) —
  **repositorio propio, no bundleado en `RubrosRepository`**, para mantener el patrón de un
  repositorio por tabla que ya tenía todo el proyecto (`ObrasRepository`/`ObraMembersRepository`/
  `CertificadosRepository`/`RubrosRepository`, cada uno una sola tabla).
- `lib/presentation/obra_detalle/screens/subitems_screen.dart` (`SubitemsScreen`) — pantalla nueva
  (no un tab embebido), empujada con `Navigator.push(MaterialPageRoute(...))` directo desde
  `rubros_tab.dart`, mismo patrón de navegación que ya usa `obras_list_screen.dart` para abrir
  `PresupuestosScreen` (las rutas nombradas de `main.dart` casi no se usan en la práctica — solo
  `/` está realmente en uso).
- `rubros_tab.dart`: `onTap` agregado al `ListTile` existente de cada rubro, sin necesitar
  `InkWell`/`GestureDetector` aparte.

**Bug real encontrado y corregido, distinto al de `.order()` de arriba**: `subitems.codigo` es
texto jerárquico ("1.1", "12.10", "12.2"...), sin columna `orden` (a diferencia de `rubros`). Un
orden por `codigo` en Supabase (o por `created_at`, que "funcionaría hoy de casualidad" por el
orden de inserción de la migración 0016) es frágil o directamente incorrecto — "12.10" ordena antes
que "12.2" lexicográficamente. Resuelto con un comparador natural en Dart dentro de
`SubitemsRepository` (separa `codigo` por `.`, compara cada segmento como número), sin necesitar
una columna `orden` nueva ni migración. Verificado en el teléfono con un rubro de más de 9 subitems.

**Sigue pendiente**: `obra_subitems` (tildar/destildar por obra, requiere `obraId`) y
`apu_composiciones`/`apu_composicion_items` (ver la composición real de una partida) — ninguno de
los dos tocado todavía.

### Costo de mano de obra: escala UOCRA y cargas sociales (Solapa 3) — schema y función completos, sin UI

Migraciones `0036` a `0040` (`supabase/migrations/`), aplicadas y verificadas en producción
(2026-09-02): tabla `escala_salarial_uocra` (catálogo compartido, seed Zona B septiembre 2026),
`insumos.categoria_uocra` (vínculo por código, no por nombre — Ayuda de Gremio se costea al valor
de Ayudante, Sereno no tiene insumo porque no participa de APU), columnas de cargas sociales +
`zona_uocra` + `vacaciones_jornales_mes` en `obra_presupuesto_config`, tabla
`obra_valor_hora_override` (el PRO fija a mano el valor hora de una categoría puntual, con
precedencia sobre el cálculo automático), y la función `calcular_valor_hora_mano_obra(obra_id,
fecha)` — verificada al centavo contra `docs/seed/costo_laboral_uocra.xlsx` en ambos extremos de la
escala (Ayudante, Oficial Especializado) y en la rama de liquidación mensual (Sereno).

**Todas las decisiones de esta pieza** (fundamento normativo de cada alícuota, por qué se descartó
el 28% de seguridad social del PDF de la liquidadora, categorías, adicional de hormigón, constantes
hardcodeadas, diseño del override, los dos multiplicadores distintos, diferencias deliberadas
contra el PDF de la liquidadora, y los pendientes abiertos con dueño) están en
`docs/costo_mano_de_obra_decisiones.md` — leer ahí antes de retomar este tema, no reabrir preguntas
ya cerradas.

**Paso 4 cerrado (2026-09-02, migraciones `0041`/`0042`)**: el consolidado de Mat y MO
(`consolidado_insumos_obra`) ya lee `calcular_valor_hora_mano_obra` — los 5 insumos de mano de obra
muestran su valor hora real en vez de "Falta cargar precio" en cuanto tienen composición cargada.
El lapicito de edición ya escribe en `obra_valor_hora_override` para mano de obra (por categoría,
nunca en `obra_insumo_precios` — filtrado con `ins.tipo != 'mano_obra'` en el propio `JOIN`, ver
`docs/costo_mano_de_obra_decisiones.md` §13), y en `obra_insumo_precios` sin cambios para
materiales.

**Paso 5, tanda 1 cerrada (2026-09-02, migración `0043`)**: primera UI real de la pieza.
`CartelCostoManoObra` (`lib/presentation/obra_detalle/tabs/cartel_costo_mano_obra.dart`), arriba de
la sección "Mano de obra" en Mat y MO — cartel informativo (multiplicador de referencia, categoría
Ayudante, siempre "aproximadamente") + tilde `aplica_cargas_sociales` (Free y PRO, de obra
entera) + desglose plegable de las 6 líneas de cargas sociales con su cita legal, leído en vivo de
`obra_presupuesto_config`. `calcular_valor_hora_mano_obra` suma `valor_hora_con_cargas`/
`multiplicador_con_cargas`, independientes del toggle, para que el cartel muestre siempre el mismo
número de referencia sin importar el modo. Detalle completo de todas las decisiones (por qué
Ayudante, por qué la aclaración de override es solo para esa categoría, por qué 6 líneas y no 4) en
`docs/costo_mano_de_obra_decisiones.md` §14.

**Paso 5, tanda 2 cerrada (2026-09-02, migraciones `0044`/`0045`) — PIEZA COMPLETA DE PUNTA A PUNTA.**
Dos ventanas separadas, no un solo diálogo (ver `docs/costo_mano_de_obra_decisiones.md` §16 para el
porqué — cuatro rondas de correcciones sobre el diseño de una sola ventana llevaron a esta
separación, no repetirlas). **Ventana 1** — `PanelValorHoraManoObra`
(`lib/presentation/obra_detalle/tabs/panel_valor_hora_mano_obra.dart`), el lapicito: solo el valor
hora de la categoría ("solo esta categoría"), con un link "Ajustar cargas sociales" que abre la
**Ventana 2** — `PanelParametrosCargasSociales`
(`lib/presentation/obra_detalle/tabs/panel_parametros_cargas_sociales.dart`), los 7 parámetros de
toda la obra (SUSS como selector con/sin certificado MiPyME, ART con aviso de que es un supuesto,
Fondo de Cese, horas mensuales/improductivas, vacaciones, zona UOCRA — etiqueta con descripción
completa vía catálogo `zonas_uocra`, texto fijo con una sola zona cargada, selector real si hay más
de una). Cada ventana tiene su propio Guardar de un solo alcance — la Ventana 2 siempre guarda los
7 sin comparar, el gate de PRO se verifica en vivo ahí, nunca en la Ventana 1. La Ventana 2 carga su
propia config al abrirse (no la recibe por constructor) para no quedar desactualizada si se reabre
sin cerrar la Ventana 1 — mismo principio que el gate de PRO en vivo, no confiar en una foto que
otro widget ya tenía (§16). **Bloqueante resuelto**: "Volver al calculado" — único, como camino
principal en la propia fila del consolidado (en ninguna de las dos ventanas), borra el
`obra_valor_hora_override` de la categoría. El "por defecto X" de los 7 campos de la Ventana 2 sale
de `CargasSocialesDefaults` (`lib/data/models/cargas_sociales_defaults.dart`), constantes Dart
copiadas a mano de los defaults reales de columna — no de la config actual de la obra (bug real,
encontrado en uso: mostraba como "por defecto" lo que el usuario acababa de escribir), ni de una
función que lea el catálogo de Postgres en vivo (evaluada y descartada por desproporcionada, §17).
Toda migración futura que cambie un default de `obra_presupuesto_config` tiene que actualizar esa
clase a mano — se avisa en el comentario de la propia clase y en el de `0046`, la primera que lo
necesitó. `0044` suma un `check`
(`horas_mensuales > horas_improductivas_mensuales`) — primera vez que esas columnas son editables
desde la app, sin el check un valor inválido rompía la división de
`calcular_valor_hora_mano_obra`. Detalle completo de esta tanda, incluida la desincronización
encontrada y corregida entre el cartel y la fila (`MatYMoTab` ahora recarga config + valor hora por
categoría junto con el consolidado), en `docs/costo_mano_de_obra_decisiones.md` §15.

**PENDIENTE CRÍTICO, no una mejora — bloqueante para repartir la app fuera de Neuquén/Río
Negro/Chubut**: solo `escala_salarial_uocra` tiene Zona B cargada, así que toda obra nueva nace ahí
por default (`zona_uocra`, `0038`) sin ningún selector visible (aparece solo con 2+ zonas) ni
ningún aviso al usuario — una obra fuera de esa región calcularía con una escala equivocada (~15-
20% de diferencia con Zona A) sin forma de notarlo ni corregirlo. Ver
`docs/costo_mano_de_obra_decisiones.md` §15, "Pendiente crítico", para las 4 zonas reales del CCT
76/75, la fuente a usar (el convenio, no resúmenes de terceros — ya se encontraron publicados
incorrectos) y la ambigüedad sin resolver sobre La Pampa.

**Sin construir**: nada pendiente de este Paso 5 — la pieza de costo de mano de obra (escala UOCRA,
cargas sociales, valor hora por categoría, consolidado, cartel, panel de edición) queda cerrada de
punta a punta. Roadmap futuro sin fecha: bot de escala UOCRA (ver
`docs/costo_mano_de_obra_decisiones.md`), conectar el bloque a la solapa APU real (sigue mock) y al
Factor K.

### Importador de Excel/PDF: diseño de datos cerrado en dos capas, sin implementar (2026-08-22)

Puerta de entrada para que un profesional suba su propio cómputo/presupuesto (Excel/PDF/foto) sin
migrar a Rubros/APU — disponible para TODOS los usuarios, con límite de documentos/mes en Free (no
es funcionalidad bloqueada para Free). Pausado al principio de su diseño al descubrir que el mapeo
final depende de Rubros/APU en Supabase (sección anterior, también sin implementar). Para no
bloquear todo, se separó en dos capas — diseño completo en `docs/importador_capa1_diseno_datos.md`,
**las 7 ambigüedades de la Capa 1 ya cerradas, pero cero migraciones escritas ni aplicadas**:

- **Capa 1 — Lectura y extracción** (diseño cerrado): tablas `importaciones` (header: `obra_id`
  **nullable** — puede importarse antes de crear la obra, ver más abajo —, `archivo_storage_path`
  obligatorio, `hojas_seleccionadas text[]` elegidas por el usuario antes de leer, `moneda_default`,
  estado `pendiente_revision`/`confirmado`/`descartado`, entrada mínima garantizada de
  `pct_avance_manual`/`monto_certificado_manual` a nivel de documento completo) +
  `importaciones_items` (filas extraídas: columnas estructuradas conocidas —
  rubro/descripción/unidad/cantidad/precio/moneda, donde `moneda` null hereda el `moneda_default`
  del header — más un `datos_originales jsonb` catch-all, mismo patrón que
  `libro_entradas.adjuntos`/`audit_log.detalle`). No depende de que exista `rubros`/`subitems` en
  Supabase — se puede implementar ya. RLS: con `obra_id` cargado, mismo criterio que `obra_subitems`
  (`is_obra_member` + `tiene_rol_en_obra('admin_maestro'|'profesional')`); con `obra_id` null, la
  fila es personal (`usuario_id = auth.uid()`) hasta que se asocie a una obra.
- **Capa 2 — Mapeo y persistencia** (no diseñada, solo interfaz reservada): columnas
  `importaciones_items.rubro_id`/`subitem_id` dejadas como `uuid` sueltos sin FK, mismo patrón que
  `modificaciones_obra.subitem_id` en Etapa 3. Le queda pendiente además resolver a qué obra se
  asocia una importación confirmada que llegó sin `obra_id`.

**Mecanismo de lectura confirmado**: Edge Function de Supabase del lado servidor llamando al LLM,
nunca desde el cliente Flutter — por seguridad (no exponer la API key en el binario) y para poder
aplicar el límite mensual de Free desde el servidor. El archivo original se guarda en Supabase
Storage (no solo el resultado de la lectura), como respaldo/trazabilidad.

**Dos decisiones citaron precedentes de piezas que no están documentadas en este archivo ni en
`docs/`** ("el importador de certificados externos" para el límite Free/PRO, "el freemium de
estimación rápida" para `obra_id` nullable) — quedaron anotadas tal como las describió el usuario,
sin poder verificarlas contra ningún doc del proyecto porque no existen todavía. Si se retoma este
tema, puede hacer falta pedirle al usuario más detalle de esas dos piezas.

**Para retomar**: nada bloquea empezar a escribir las migraciones de Capa 1 (todas las ambigüedades
de diseño de datos están cerradas) salvo el detalle fino de la Edge Function (prompt, formato de
respuesta, manejo de errores), que todavía no se diseñó. Capa 2 sigue esperando el listado semilla
de macrorrubros de la pieza de Rubros/APU.

### Currency and formatting

`core/utils/currency_formatter.dart` (`CurrencyFormatter.formatARS/formatUSD/formatByCurrency`) is the intended shared formatter, but most screens instead define their own local `_formatearMonto`/`_fmt` method (regex-based thousands separator, e.g. in `obras_list_screen.dart`, `presupuestos_screen.dart`, `rubros_tab.dart`) rather than reusing it. Prefer `CurrencyFormatter` in new code rather than adding another local copy.

### Screen size and structure

Screens under `presentation/` are large, self-contained `StatefulWidget`s (500–1000+ lines) that build dialogs, bottom sheets, and tab content as private `_build*` methods on the `State` class rather than extracting separate widget files. This is the established pattern here — follow it for consistency rather than pre-emptively splitting files, unless a screen grows unwieldy and the user asks for a refactor.

### Dependencies not yet used in code

`pubspec.yaml` declares `local_auth`, `pdf`, `printing`, and `path_provider`, but no file under `lib/` currently imports them — these are provisioned for planned features (biometric auth, PDF export of legajos/presupuestos) that aren't implemented yet.
