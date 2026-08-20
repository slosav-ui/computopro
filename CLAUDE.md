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
  **Estado real en `lib/` (sin cambios — la brecha de UI/Dart sigue intacta)**: `lib/presentation/obra_detalle/tabs/gestion_obra_tab.dart` implementa solo **3 de los 5 estados** (`Borrador` → `Emitido (Esperando Pago)` → `Pagado`, ver `_cambiarEstado`/`_getColorEstado`). Faltan por completo *Leído por Propietario* y *Impactado y Cerrado*. Hay un botón "Subir PDF Firmado" pero **no bloquea** la emisión del siguiente certificado. No se genera ningún PDF real (los paquetes `pdf`/`printing` siguen sin usarse en todo `lib/`). El plazo de pago (`_diasPlazoPago`) es un campo fijo sin UI para configurarlo. Y el tab **no está conectado** a `PresupuestosScreen` (usa un `obraId` requerido que nadie le pasa hoy).
  **Pero la capa de datos en Supabase ya está completa y en producción** (2026-08-20) — ver sección "Ciclo de vida del Certificado de Obra: capa de datos completa" más abajo. `gestion_obra_tab.dart` simplemente no consume nada de eso todavía; conectarlo (reemplazar el mock por la tabla `certificados` real) es la brecha de UI que queda pendiente, no un problema de diseño de datos.
- **Matriz de permisos por tipo de relación cliente-obra** — 3 relaciones con visibilidad distinta: *Cliente Autoconstructor* (ve todo, costos directos y precios reales de corralón), *Cliente con Profesional + Contratista* (ve precio final y avance; oculto: salarios, gastos generales, beneficio, imprevistos y precios negociados en bruto — solo Profesional/Contratista cargan, Cliente aprueba en modo lectura), *Cliente con Contratista Directo sin Profesional* (visibilidad más restringida aún: ve avance y precio del rubro certificado, oculto el costo interno y margen del contratista).
  **Estado real**: **no implementada**. `gestion_obra_tab.dart` solo tiene un `DropdownButton` binario (`'Profesional / Empresa'` vs `'Propietario / Cliente'`) sin relación con estos 3 casos, y el resto del código no modela ningún concepto de "tipo de relación cliente-obra".
- **Motor "Mandar a Presupuestar"** (botón inteligente en Resumen Final) — dispara una solicitud zonal simultánea a 3 corralones geolocalizados en la zona de la obra; los precios devueltos se muestran etiquetados como no firmes hasta una validación manual obligatoria ("Validar y Confirmar Precios"); exportación alternativa a PDF/Excel/texto WhatsApp; si no hay comercios con membresía activa en la zona, calcula un promedio automático sobre 1 a 4 proveedores de referencia.
  **Estado real**: **no implementado**, ningún archivo del proyecto lo referencia. `resumen_tab.dart` solo calcula y muestra el desglose de costos/coeficientes, sin ningún botón ni lógica de cotización a proveedores.
- **Modo "Carga Externa de Presupuesto"** (transversal a varias solapas) — permite ingresar presupuestos cerrados o montos "llave en mano" sin pasar por el desglose de APU, pensado para quien solo necesita gestión y no cálculo técnico. Se ofrece en el Alta de Obra o inmediatamente después de crearla. Dos niveles (roadmap, no implementar todavía):
  - **Nivel 1 — Presupuesto con Plantilla**: el usuario descarga una plantilla Excel estandarizada (columnas fijas: Rubro, Descripción, Unidad, Cantidad, Precio Unitario opcional), la completa con sus propios datos y la sube. La app lee esa plantilla y puebla automáticamente `ObraModel`/`Rubro`/`Subitem`, habilitando: listado de materiales automático (cruzando contra la tabla `insumos`), cotización a proveedores/corralones cercanos (reutilizando el motor de precio promedio ya documentado en "Solapa Proveedores"), cálculo de mano de obra vía escala UOCRA, y certificaciones con datos reales en Gestión de Obra.
  - **Nivel 2 — Carga Libre**: el usuario sube su propio PDF/Excel con cualquier formato, sin adaptarse a la plantilla. La app NO puede leer ese contenido; el archivo queda solo como documento de referencia/respaldo. Al elegir este nivel hay que mostrar un aviso explícito antes de confirmar, aclarando que el usuario deberá armar manualmente: listado de materiales, solicitud de precios a proveedores y certificados de avance — la app no automatiza nada a partir de este archivo. Lo que sí queda disponible en este nivel: comunicación entre roles (Constructor/Profesional/Propietario) y carga manual básica de avance/certificados en Gestión de Obra.
  - Al activar cualquiera de los dos niveles debería ocultar los enlaces a APU y habilitar directamente la Solapa de Gestión de Obra para arrancar el control de avance.
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
```

**Supabase credentials**: `lib/main.dart` calls `Supabase.initialize()` reading `SUPABASE_URL`/`SUPABASE_ANON_KEY` via `String.fromEnvironment` — a plain `flutter run` (no `--dart-define-from-file`) will initialize with empty values and fail. Copy `env.example.json` to `env.json` (gitignored, never commit it) at the repo root, fill in the real values from the Supabase dashboard (Project Settings → API), and always run/build with `--dart-define-from-file=env.json`.

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

**No implementado todavía**: ninguna conexión a Dart/UI (`gestion_obra_tab.dart` sigue siendo el
mock de siempre, ver más arriba en "Verificación de implementación"); la matriz de permisos por tipo
de relación cliente-obra (Cliente Autoconstructor / con Profesional+Contratista / con Contratista
Directo) sigue sin ningún soporte de datos, es una capa de visibilidad aparte que no cambia el
schema de `certificados`; y la generación real de PDF (paquetes `pdf`/`printing` siguen sin usarse en
todo `lib/`) — el "PDF firmado" de acá es solo un adjunto (`text[]` de URLs) que alguien sube desde
afuera, no algo que la app genere.

### Currency and formatting

`core/utils/currency_formatter.dart` (`CurrencyFormatter.formatARS/formatUSD/formatByCurrency`) is the intended shared formatter, but most screens instead define their own local `_formatearMonto`/`_fmt` method (regex-based thousands separator, e.g. in `obras_list_screen.dart`, `presupuestos_screen.dart`, `rubros_tab.dart`) rather than reusing it. Prefer `CurrencyFormatter` in new code rather than adding another local copy.

### Screen size and structure

Screens under `presentation/` are large, self-contained `StatefulWidget`s (500–1000+ lines) that build dialogs, bottom sheets, and tab content as private `_build*` methods on the `State` class rather than extracting separate widget files. This is the established pattern here — follow it for consistency rather than pre-emptively splitting files, unless a screen grows unwieldy and the user asks for a refactor.

### Dependencies not yet used in code

`pubspec.yaml` declares `local_auth`, `pdf`, `printing`, and `path_provider`, but no file under `lib/` currently imports them — these are provisioned for planned features (biometric auth, PDF export of legajos/presupuestos) that aren't implemented yet.
