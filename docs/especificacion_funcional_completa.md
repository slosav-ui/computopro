# Especificación funcional completa — ComputoPRO
> Extraída y organizada a partir de meses de conversación con Gemini (documento original de 150.000 líneas). Este resumen prioriza decisiones de negocio y arquitectura funcional, no código.

## 1. Posicionamiento y modelo de negocio

- App **B2B / nicho profesional**, no de consumo masivo. El usuario final (dueño de casa) no paga por apps de cálculo; el foco es en **arquitectos, maestros mayores de obra, constructores independientes y estudios chicos** en Argentina.
- Regla explícita: **evitar scope creep**. Priorizar el MVP (cómputo, APU, materiales, resumen de obra) y dejar ideas futuras en backlog.
- Nombres evaluados: ComputoPRO, Constructo (descartado por nombre ocupado), otros. Quedó **ComputoPRO**.
- Plan de negocio en 3 etapas: (1) corto plazo — validación y MVP pulido; (2) mediano plazo — definir nicho y monetización; (3) largo plazo — ecosistema B2B y features premium.

## 2. El "quiebre" — diagnóstico de por qué se perdía código

Gemini mismo diagnosticó el problema (esto es la causa raíz de la migración a Claude Code):
> "El desvío ocurrió cuando comenzamos a tocar y modificar en bloque los códigos de la interfaz sin seguir el método quirúrgico archivo por archivo. Al intentar acelerar e integrar widgets complejos, el código monolítico empezó a sobreescribirse, rompiendo la modularidad."

Reglas de trabajo que el usuario impuso después de esto (y que **ya están reflejadas en el CLAUDE.md del proyecto**):
- Trabajo prolijo y paso a paso, archivo por archivo, cero cambios masivos.
- Antes de modificar, explicar el porqué técnico y pedir el código actual para analizarlo.
- Respeto absoluto al estado que ya funciona.

### Funcionalidades que se perdieron en una reescritura y debían recuperarse en `obras_list_screen.dart`:
- **Cotización USD**: banda oficial BNA (compra/venta + promedio) — no un valor fijo hardcodeado.
- **Proyección de dólar personalizada (PRO)**: campo editable + botón de reseteo a valor BNA.
- **Mapa de Obras**: modal interactivo con vista satelital y listado georreferenciado (no un SnackBar de texto).
- **Alta de Obra**: selector de tipo de obra, selector de moneda base, advertencia legal sobre legajos/carátulas.
- **Servicios Especiales**: modal con checklist de opciones técnicas + adjuntar planos PDF/DWG (no lista de texto plano).
- **Modal Plan PRO**: BottomSheet completo con desglose de beneficios (IRAM K/G/Q, CAC, exportación), no un texto genérico.
- **Ajuste Económico & Moneda**: modal para alternar ARS/USD y activar/desactivar CAC por obra.

## 3. Arquitectura de carpetas (Clean Architecture) — ya implementada

```
lib/
├── core/           # constants, security (UserContext/roles), theme, utils
├── data/           # datasources, models (ObraModel, Rubro, Subitem, Insumo), repositories
├── domain/         # entities, repositories (contratos), usecases
└── presentation/
    ├── dashboard/      # ObrasListScreen (pantalla principal)
    └── obra_detalle/
        ├── screens/    # PresupuestosScreen (contenedor de solapas)
        └── tabs/       # las 6 solapas
```

## 4. Pantalla Principal / Dashboard (ObrasListScreen) — "Centro de Control y Permisos"

No es un simple listado: resuelve autenticación, enrutamiento, asignación de roles y accesos por QR.

- **Inicio abierto**: cualquier actor (Cliente, Profesional o Constructor) puede iniciar un proyecto.
- Al crear una obra, el creador queda por defecto como **Administrador**, con opción de cambiarlo.
- Tras el alta, debe **redirigir automáticamente** a la ventana de gestión de permisos de esa obra.
- **Generación de QR / invitación**: contextual, disponible desde el Dashboard o cualquier solapa, para vincular colaboradores.
- **Notificación al Admin**: cuando un colaborador con permiso de edición hace una acción sensible (modificar cómputo, avance), se genera una alerta automática al Administrador.
- El generador de QR **no va en el Dashboard principal** (decisión explícita, para no romper la limpieza visual) — va en Configuración Global o Ajustes de obra.
- **Control de acceso obligatorio**: bloquea navegación a cualquier solapa si no hay obra seleccionada/creada.

### Roles de proyecto
`admin_maestro`, `profesional`, `constructor`, `cliente_principal`, `invitado_veedor`, `invitado_apoderado`.

### Matriz de visibilidad por rol
- **Caja Blanca (100% acceso)**: `admin_maestro`, `profesional` — edición total de cómputos, APU, precios, coeficientes, aprobaciones.
- **Vista Operativa (sin montos)**: `constructor`/capataz — cómputos y avance diario, sin valores monetarios.
- **Caja Negra Comercial**: `cliente_principal` — totales, avances, certificados, reportes ejecutivos, sin APU ni coeficientes internos.
- **Caja Negra Básica (lectura pasiva)**: `invitado_veedor` — solo lectura de avances y fotos.
- **Invitado Apoderado**: hereda vista de cliente, pero desbloquea firma/aprobación de certificados dentro de rangos de fecha/monto autorizados por el titular (Panel de Delegación de Firma, con registro en Audit Log).

### Blindaje legal
- Términos y Condiciones / EULA de aceptación obligatoria.
- Moderación de contenido, posibilidad de bloqueo de cuenta (`isBlocked`).
- **Audit Log inalterable**: quién hizo qué, cuándo, bajo qué rol — para deslindar responsabilidad legal ante mal uso.

## 5. Las 6 Solapas (dentro de PresupuestosScreen)

### Solapa 1 — Cómputo y Presupuesto (rubros_tab.dart)
- Catálogo de +50 rubros organizados por macrorrubros (Steel Frame, Wood Frame, Sistemas Livianos, Estructuras Metálicas, Mampostería, etc.).
- **Free**: tildar/destildar subítems del catálogo predeterminado.
- **Pro**: crear/editar/eliminar rubros y subítems personalizados.
- Vínculo bidireccional con Solapa 2 (APU).
- Recibe `precioUnitario` desde Solapa 3. Envía cantidades/catálogo a Solapa 4 y Solapa 6.

### Solapa 2 — Análisis de Precios Unitarios / APU (analisis_precios_tab.dart)
- Guarda la "receta teórica" por unidad (ej: kg de cemento, m³ de arena, horas de Oficial UOCRA por m²).
- Desacopla el rendimiento teórico de la inflación (los rendimientos son fijos; los valores monetarios vienen de Solapa 3).
- **Principio de confidencialidad**: el Constructor NO tiene acceso a esta solapa (o solo ve cómputo sin precios teóricos). El Profesional ve cómputos y precios finales en Solapa 1/4, pero el Coeficiente K permanece aislado y privado en Solapa 3.

### Solapa 3 — Materiales y Mano de Obra (mano_obra_tab.dart)
- Escala salarial UOCRA (Oficial Especializado, Oficial, Medio Oficial, Peón), actualizada según paritarias oficiales.
- Catálogo de +200 insumos frecuentes de construcción argentina.
- Cálculo del **Coeficiente K** (multiplicador global o por macrorrubro) — panel de configuración totalmente privado del Admin/Profesional.
- Zonificación geográfica con coeficientes de flete/zona.

### Solapa 4 — Proveedores (proveedores_tab.dart)
- **Modelo de doble motor de precios**:
  1. Corralón adherido (paga canon/suscripción, bot/API sincroniza stock/precios en tiempo real o cada 24h).
  2. Si no hay corralón adherido en la zona, algoritmo de scraping/promedio sobre 3 proveedores predefinidos de la región — garantiza que nunca haya una lista vacía.
- Algoritmo de ranking tipo "Mercado Libre": más relevantes / menor precio / más cercanos.
- Monetización: cánones de corralones B2B + publicidad orgánica "Corralón Destacado" sin saturar la UX.
- Persistencia agregada: los proveedores ya no se pierden al reiniciar la app (antes sí se perdían).
- **Backend elegido: Supabase** (PostgreSQL, plan gratuito, región sa-east-1/São Paulo) — recomendado sobre Firebase por consultas relacionales más ordenadas para este dominio.

### Solapa 5 — Gestión de Obra (gestion_obra_tab.dart)
- Calendario/Gantt de avance físico y financiero.
- Curva de inversión: proyectado vs. real ("Curva en S").
- Emisión de Certificados de Obra en PDF firmables (paquetes `pdf` y `printing`).
- Circuito: Contratista carga avance → Profesional aprueba → PDF oficial → notificación al cliente → cobro → subida de comprobante (cierre contable).
- Fondo de Reparo con deducción automática en el certificado.
- Matriz de permisos: Contratista solo edita ítems asignados; Propietario en modo lectura/auditoría.

### Solapa 6 — Resumen Final (resumen_tab.dart)
- Consolidado: Costo Directo + Coeficientes de Pase + Impuestos = Precio Total de Venta.
- Botón "Mandar a Presupuestar" que conecta con el motor de cotización.
- **Exportación PDF**:
  - Free: con marca de agua diagonal cruzada.
  - Pro: legajo limpio, con logo del estudio y firma de pie de página.

## 6. Lógica Free vs. Pro (transversal a todas las solapas)

- Free: opera con catálogo estándar, coeficientes de referencia bloqueados (solo lectura), exportación con marca de agua.
- Pro: edición libre de coeficientes/rendimientos, con cartel de advertencia de responsabilidad técnica antes de modificar variables críticas (silenciable por solapa). Exportación limpia con marca propia.
- Precio de referencia usado como mockup: **$15.000 ARS/mes** o **USD 12/mes**, con botón preparado para Mercado Pago/Stripe.

## 7. Roadmap explícitamente pospuesto (no construir todavía, pero dejar arquitectura abierta)

- **Marketplace interno de terceros**: patrón Provider/Adapter para que una tarea (`JobTask`) pase de `internal` a `outsourced`, con campos `asignadoA_id` y `estadoRevision`.
- Persistencia local + sincronización remota (offline-first vía SQLite/Hive en móvil, sync con Supabase al recuperar conexión).
- Geolocalización personalizada por obra/usuario.

## 8. Problemas técnicos recurrentes documentados (para contexto, no acción inmediata)

- Errores repetidos de compilación Gradle (`assembleDebug failed`) vinculados a versiones de Android Gradle Plugin (AGP) y el paquete `file_picker`.
- Warning recurrente: actualizar AGP a versión ≥ 8.11.1.
- Recomendación ya explorada: reemplazar `file_picker` por `file_selector` para evitar conflictos de dependencias nativas.
