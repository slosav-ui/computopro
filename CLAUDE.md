# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Idioma de respuesta

Responder siempre en español al trabajar en este repositorio, sin importar el idioma de este documento.

## Project

Flutter app (`mi_primera_app` in `pubspec.yaml`) for managing construction projects ("obras") and their budgets ("presupuestos") in the Argentine construction market. UI, domain terms, and comments are in Spanish (rioplatense/Argentine): APU = Análisis de Precios Unitarios (unit price analysis), CAC = índice de la Cámara Argentina de la Construcción (cost adjustment index), IRAM = Argentine technical standards body, UOCRA = construction workers' union (referenced for cargas sociales / payroll charges).

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
