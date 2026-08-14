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

## Especificación funcional y de negocio (resumen de `docs/especificacion_funcional.md` y `_2.md`)

Ambos archivos son transcripciones de conversaciones de diseño con el usuario (no specs formales; el segundo repite gran parte del primero y cierra con una versión más concreta y superadora de las decisiones). Esto es la referencia funcional/de producto permanente del proyecto — el código actual todavía no implementa la mayoría de estos puntos, son el objetivo a futuro.

### Posicionamiento y modelo de negocio

ComputoPRO es una herramienta **B2B / de nicho profesional**, no una app masiva de consumo. Target: arquitectos, maestros mayores de obra, constructores independientes y estudios chicos que manejan entre 2 y 10 obras simultáneas en Argentina. Monetización: suscripción SaaS mensual/anual (no publicidad, no venta única). Regla de proceso acordada explícitamente con el usuario: **evitar scope creep** — priorizar el MVP (cómputo, APU, materiales, resumen de obra) y dejar ideas futuras en un backlog, sin desviarse del nicho ni intentar ser una app para "cualquier usuario". Antes de escribir código para una funcionalidad nueva de negocio, el usuario prefiere primero una ronda de feedback/alineación.

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
