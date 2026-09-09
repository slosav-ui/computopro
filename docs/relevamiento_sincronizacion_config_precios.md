# Relevamiento: qué está conectado con qué (2026-09-09)

Disparado por 5 bugs reales encontrados por casualidad en los últimos días, todos del mismo tipo:
una pieza se construyó apuntando a lo que existía en ese momento, después eso cambió, y nadie
revisó qué quedó apuntando a lo viejo. Este documento releva sistemáticamente cuatro patrones
donde ese tipo de bug puede repetirse. **Solo relevamiento — nada de lo listado acá se tocó.**

Convención de esta lista: **por gravedad, no por orden de hallazgo.** Cada ítem dice si es un bug
**confirmado** (verificado por inspección de código/esquema — determinístico, no hace falta
reproducirlo para saberlo cierto) o una **sospecha** (posible, no verificado). Al final, lo que se
revisó y está bien conectado.

## Resumen ejecutivo

| # | Hallazgo | Gravedad | Estado |
|---|----------|----------|--------|
| 1 | Certificación calcula sin Factor K | Alta — plata real | Confirmado, YA CONOCIDO (2026-09-08), pendiente |
| 2 | FK `certificado_subitems_avance.obra_subitem_id` bloquea borrado de rubro/subítem propio ya certificado | Alta — bloquea una operación con datos reales de por medio | Confirmado por esquema, no reproducido en vivo |
| 3 | "Ajuste Económico y Moneda" sigue escribiendo `obras.monto_total` estático | Media — escritura muerta, no se lee para mostrar nada hoy | Confirmado |
| 4 | Toggle `obras.aplicaCac` no aplica ningún ajuste — es 100% cosmético | Media — puede inducir al usuario a creer que su presupuesto se actualiza solo | Confirmado |
| 5 | `obra_presupuesto_config.tipo_suelo` / `zona_sismorresistente` sin lector | Baja — pieza nunca construida, no una que se rompió | Confirmado |
| 6 | Fórmula de precio promedio de insumo duplicada (función + inline) | Baja — no divergió todavía | Confirmado, bajo riesgo |
| — | Otras FKs sin acción de borrado (`apu_composicion_items.insumo_id`, `obra_insumo_precios.corralon_id`, `modificaciones_obra.apu_privado_id`, `auth.users`, catálogos UOCRA) | — | Sin acción de borrado, pero sin ruta de UI que las dispare hoy |

---

## 1 · Funciones SQL de cálculo de precios: quién llama a cada una

Mapa completo de las funciones `calcular_*` relacionadas con precios/montos, con quién las llama.

```
calcular_composicion_detalle_subitem (detalle insumo x insumo de una composición)
  └─ calcular_factor_k_subitem (cascada completa: GG/Imprevistos/EPP/CF/Beneficio/Impuestos)
       └─ calcular_precio_final_apu_subitems (0090/0092 — batch, LATERAL)
            ├─ ApuComposicionesRepository.calcularPreciosSubitems → Cómputo (SubitemsScreen) y
            │  listado de Solapa APU (ApuListadoTab)
            └─ calcular_presupuesto_vivo_obra (0091) → total del dashboard (ObrasListScreen)
  └─ BloqueFactorKPartida (Dart) → llamada directa, muestra el desglose línea por línea

calcular_precio_apu_subitems (0059 — SIN cascada, precio de insumos/mano de obra puro)
  └─ calcular_monto_obra_subitems (0052)
       ├─ calcular_monto_periodo_avance (trigger) → certificado_subitems_avance.monto_periodo
       │    └─ calcular_totales_certificado (0054) → vista previa Y emitir_certificado
       │         (comparten la misma función — bien resuelto, no hay divergencia acá)
       └─ calcular_avance_ponderado_rubros/obra (0052) → peso para % de avance en Gestión de Obra

calcular_valor_hora_mano_obra (0039/0043)
  ├─ calcular_composicion_detalle_subitem (valor hora de insumos tipo mano_obra)
  ├─ consolidado_insumos_obra (0031/0042, Mat y MO)
  └─ CartelCostoManoObra / PanelValorHoraManoObra (Dart, cartel informativo)

calcular_precio_promedio_insumo (0013)
  └─ consolidado_insumos_obra (fallback cuando no hay precio manual ni valor hora)
```

### Hallazgo #1 — Certificación calcula sin Factor K — **CONFIRMADO, YA CONOCIDO**

`calcular_monto_obra_subitems` sigue llamando a `calcular_precio_apu_subitems` (la versión SIN la
cascada de Factor K), y de ahí cuelga **todo** lo monetario de Gestión de Obra: el snapshot
`certificado_subitems_avance.monto_periodo`, `certificados.monto` (vía `emitir_certificado` y
`calcular_totales_certificado`), y el peso usado en `calcular_avance_ponderado_rubros/obra`. Se
construyó el 2 de septiembre, antes de que existiera Factor K (`calcular_factor_k_subitem`,
0077/0078, varios días después), y nadie la reconectó cuando la cascada se construyó.

**Consecuencia para el usuario:** todo certificado emitido hasta hoy factura al cliente el costo
puro de insumos y mano de obra — sin Gastos Generales, Imprevistos, EPP, Costo Financiero,
Beneficio ni Impuestos. La diferencia no es un redondeo.

Ya documentado en `supabase/migrations/0091_presupuesto_vivo_obra.sql` (sección "PENDIENTE
ANOTADO") y confirmado por Seba el 2026-09-08 como bug real, pendiente en Gestión de Obra. Este
relevamiento no agrega nada nuevo acá — solo lo repite en el mapa completo para que quede a la
vista junto con el resto de la cadena.

**Verificado, no roto:** la vista previa del certificado (`calcular_totales_certificado`) y la
emisión (`emitir_certificado`) comparten la MISMA función — no hay una segunda implementación de
la cuenta que pueda divergir entre lo que el usuario ve antes de emitir y lo que se congela al
emitir. El problema es que la fuente común está mal en la raíz, no que haya dos fuentes distintas.

---

## 2 · Configuración que se guarda pero nadie lee

Columna por columna de `obra_presupuesto_config`, `obras` y `perfiles` — quién escribe, quién lee.

### `obra_presupuesto_config`

| Columna | Quién escribe | Quién lee | Estado |
|---|---|---|---|
| `tipo_presupuesto` | `SelectorTipoPresupuesto` | `calcular_precio_final_apu_subitems` (0090) | Conectado |
| `aplica_impuestos` | `SelectorTipoPresupuesto` | `calcular_precio_final_apu_subitems` (0092, corregido en esta sesión) | Conectado (recién arreglado) |
| `gg_pct` / `imprevistos_pct` / `epp_pct` / `costo_financiero_pct` / `beneficio_pct` / `gestion_materiales_terceros_pct` | `PanelEditarFactorK` | `calcular_factor_k_subitem` | Conectado |
| `art_pct` / `fondo_cese_pct` / `suss_pct` / `fijos_operario_mensual` / `horas_mensuales` / `horas_improductivas_mensuales` / `obra_social_patronal_pct` / `fics_pct` / `ieric_pct` / `fodeco_pct` / `uocra_empleador_pct` / `aplica_cargas_sociales` / `vacaciones_jornales_mes` / `zona_uocra` | Paneles de Costo de Mano de Obra (`CartelCostoManoObra`/`PanelValorHoraManoObra`) | `calcular_valor_hora_mano_obra` (0043) — las 14 columnas, ninguna sin usar | Conectado, íntegro |
| `tipo_suelo` | Nadie (solo el default del trigger de alta) | Nadie | **Hallazgo #5 — sin conectar** |
| `zona_sismorresistente` | Nadie (solo el default del trigger de alta) | Nadie | **Hallazgo #5 — sin conectar** |

### `obras`

| Columna | Quién escribe | Quién lee | Estado |
|---|---|---|---|
| `monto_total` | Alta de obra (siempre 0.0, 0087), **y el diálogo "Ajuste Económico y Moneda" de `ObrasListScreen`** | Nadie (el dashboard usa `calcular_presupuesto_vivo_obra`, no esta columna) | **Hallazgo #3 — escritura muerta** |
| `aplica_cac` | Diálogo "Ajuste Económico y Moneda" | Solo el propio `ObrasListScreen` (para pintar la advertencia y un badge) — ninguna función SQL, ningún cálculo de precio | **Hallazgo #4 — cosmético, no hace nada** |
| `anticipo_pct` / `fondo_reparo_pct` / `dias_plazo_pago_certificados` | Sin pantalla de edición encontrada (deuda ya documentada en otra pieza) | `emitir_certificado` / `calcular_totales_certificado` | Conectado del lado de lectura; falta UI de escritura (fuera de este relevamiento) |
| `monto_total_contratado` | `aprobar_ajuste_contrato` (0008) | `calcular_avance_hitos` (Modelo B) | Conectado |
| `id_admin_creador`, `moneda`, `mes_base_cac`, `revision`, `superficie_m2`, `ubicacion`, `propietario`, `nombre`, `tipo_obra`, `perfil_creador`, `estado` | `ObrasListScreen` (alta/edición) | Mostrados directamente, sin cálculo derivado | Conectado (son datos descriptivos, no calculados) |

### `perfiles`

| Columna | Quién escribe | Quién lee | Estado |
|---|---|---|---|
| `es_pro` | Nadie desde la app (a propósito — deuda técnica ya documentada: solo SQL Editor hasta que exista sistema de pagos) | Todos los gates PRO/Free de la app | Conectado del lado de lectura; la falta de escritura real es una decisión ya conocida, no un bug |

### Hallazgo #5 — `tipo_suelo` / `zona_sismorresistente` — **CONFIRMADO, baja gravedad**

Ninguna función SQL las lee (grep completo sobre `supabase/migrations/`), y ningún archivo de
`lib/` las modela ni las edita (`ObraPresupuestoConfig` las excluye explícitamente, con comentario
propio explicando por qué). A diferencia de los otros hallazgos, esto no es algo que se rompió: es
la pieza de "cálculo sismorresistente" del diseño original de Rubros/APU que nunca se construyó.
Las columnas existen con su default desde 0020, sin consecuencia real porque nadie las tocó nunca
en ninguna dirección.

### Hallazgo #4 — `obras.aplicaCac` no aplica ningún ajuste — **CONFIRMADO, gravedad media**

El toggle vive en el diálogo "Ajuste Económico y Moneda" de `ObrasListScreen`. Cuando está
apagado, muestra esta advertencia (texto real del código, `obras_list_screen.dart`):

> "Sin el ajuste por CAC, este presupuesto en pesos queda fijo: no se actualiza solo con el costo
> de la construcción."

Esa frase implica que, con el toggle **prendido**, el presupuesto SÍ se ajusta solo por un índice
CAC. Búsqueda completa: no existe ninguna tabla de índice CAC, ninguna función SQL que lo aplique,
ni ningún lugar del código que multiplique un monto por una variación CAC. `aplica_cac` se guarda
en la base y se lee — pero solo por la misma pantalla que lo escribió, para pintar el badge y la
advertencia. Ninguna función de precio (`calcular_precio_final_apu_subitems`,
`calcular_presupuesto_vivo_obra`, `calcular_totales_certificado`) lo mira.

**Consecuencia para el usuario:** un usuario que prende el toggle puede creer que su presupuesto en
pesos se está ajustando automáticamente por inflación de la construcción. No es así — ese
presupuesto queda exactamente tan fijo con el toggle prendido como apagado. El único ajuste real
que existe hoy es el que ya documentó `precio_congelado_vs_recalculado` (memoria del proyecto): el
precio se recalcula solo si cambian los insumos/mano de obra subyacentes, nunca por un coeficiente
CAC — ese mecanismo de coeficiente pactado nunca se construyó.

**Relacionado, no es el mismo bug pero es la misma familia:** la cotización de dólar que usa
`ObrasListScreen` para las conversiones ARS/USD (`_dolarBnaCompra`/`_dolarBnaVenta = 1340/1390`,
etiquetada "Agosto 2026 (BNA)") y los indicadores CAC que se muestran en el dashboard
(`_variacionCacUltimoMes = 3.8`, `_ultimoMesPublicadoCac = 'Julio 2026'`) son **constantes
hardcodeadas en Dart**, no datos vivos ni columnas de ninguna tabla. No es un caso de
desincronización (nunca estuvieron conectados a nada real) — es mock conocido, se anota acá solo
para que no se confunda con el toggle de CAC si se decide encarar cualquiera de las dos piezas.

---

## 3 · Valores mostrados que no se recalculan

### Hallazgo #3 — `obras.monto_total` sigue recibiendo escrituras estáticas — **CONFIRMADO, gravedad media**

Ya se corrigió una vez (0087: tres obras con `monto_total` contaminado por una fórmula de
superficie; 0091: el dashboard pasó a usar `calcular_presupuesto_vivo_obra` en vez de esta
columna). Pero el diálogo **"Ajuste Económico y Moneda"** de `ObrasListScreen` (el mismo que
edita moneda/CAC) todavía hace esto al guardar:

```dart
final double montoTotalAnterior = (obra['montoTotal'] as num?)?.toDouble() ?? 0.0;
final double nuevoMontoTotal = monedaSeleccionada == monedaAnterior
    ? montoTotalAnterior
    : _convertirMonto(montoTotalAnterior, monedaAnterior, monedaSeleccionada);
...
await _obrasRepository.actualizarObra(obra['id'] as String, {
  ...
  'montoTotal': nuevoMontoTotal,
});
```

Convierte el total (que en memoria ya es el presupuesto vivo recién calculado, no el viejo
estático) y lo persiste de nuevo en `obras.monto_total` — la misma columna que 0091 dejó de usar
como fuente de verdad. Hoy no tiene consecuencia visible porque nada vuelve a leer esa columna
para mostrar algo (el próximo `_cargarObras()` la pisa con el valor en vivo otra vez) — pero es
exactamente el mismo patrón de fondo que causó el bug original del dashboard: una pieza (este
diálogo) se escribió cuando `monto_total` todavía era la fuente de verdad, y nadie la revisó
cuando eso cambió en 0091. Si algún día alguna función SQL empieza a leer `monto_total`
directamente (una migración futura, una consulta administrativa, un reporte), va a recibir un
número potencialmente viejo sin ningún aviso.

**No revisado en este relevamiento, fuera de foco:** si hay otras pantallas que también escriban
`montoTotal` sin pasar por `calcular_presupuesto_vivo_obra`. La búsqueda de escrituras (`git grep
"montoTotal':"`) solo encontró las dos ya conocidas (alta de obra → 0.0, este diálogo).

**Verificado, no es un problema:** `certificados.monto` (snapshot al emitir, por diseño — el
certificado no se mueve si el precio de la partida cambia después) y `obras.monto_total_contratado`
(fuente de verdad de Modelo B, escrito atómicamente por `aprobar_ajuste_contrato`) son casos
DISTINTOS — ahí el valor guardado es la respuesta correcta a propósito, no algo que debería
derivarse en vivo de otra cosa.

---

## 4 · Claves foráneas sin acción de borrado

Repaso completo de toda referencia `references tabla(columna)` en `supabase/migrations/`,
clasificada por si el usuario tiene, hoy, alguna forma de disparar el DELETE del lado padre desde
la app.

### Ya corregidas en esta sesión (contexto, no hace falta volver a tocarlas)

| FK | Acción actual | Migración |
|---|---|---|
| `importaciones_items.subitem_id` → `subitems(id)` | `SET NULL` | 0088 |
| `modificaciones_obra.subitem_id` → `subitems(id)` | `SET NULL` | 0088 |
| `importaciones_items.rubro_id` → `rubros(id)` | `SET NULL` | 0093 |

### Sin acción de borrado, y SÍ alcanzables desde la app hoy

| FK | Referenciada por | Cómo se dispara | Gravedad |
|---|---|---|---|
| `certificado_subitems_avance.obra_subitem_id` → `obra_subitems(id)` | — | Borrar un rubro/subítem **propio** que ya tenga avance certificado en alguna obra. La cascada es `rubros`→`subitems`(0016, cascade)→`obra_subitems`(0028, cascade)→**se frena acá**, porque esta FK no tiene cascade/set null. **Hallazgo #2.** | **Alta — bloquea con datos de certificación de por medio, mismo síntoma que los bugs 0088/0093 (error genérico en pantalla, real 23503 en consola con el fix reciente de `_onEliminarRubro`)** |

### Hallazgo #2 — detalle

`certificado_subitems_avance` (0052) apunta a `obra_subitems(id)` sin `on delete cascade` ni `set
null` — a diferencia de casi todo el resto de la cadena, que sí lo tiene. El único camino para que
Postgres intente borrar una fila de `obra_subitems` es la cascada que dispara borrar un rubro o
subítem **propio** del catálogo (0028) — no hay ningún DELETE directo sobre `obra_subitems` en
`lib/` (confirmado, `obra_subitems_repository.dart` no tiene ningún método de borrado).

Caso concreto que lo dispara: un PRO crea un rubro propio, carga cómputo con él en una obra, avanza
la obra y **certifica** ese avance (fila en `certificado_subitems_avance`), y después intenta
borrar ese rubro propio desde `RubrosTab`. La cascada llega hasta `obra_subitems` y se frena ahí —
mismo síntoma exacto que los bugs 0088 y 0093 recién corregidos (23503, con el diálogo de
confirmación ya mostrado y aceptado por el usuario).

**Por qué "confirmado, no reproducido"**: no se armó el caso real (crear rubro propio → certificar
avance → intentar borrar) para verlo fallar en el emulador, pero el comportamiento de Postgres ante
una FK sin acción de borrado es determinístico — no hace falta reproducirlo para saber que bloquea.

**Decisión pendiente (no tomada en este relevamiento, es implementación):** igual que 0088/0093,
la pregunta es `SET NULL` vs. avisar y no dejar borrar. A favor de `SET NULL`: mismo criterio ya
usado dos veces — el certificado emitido es un documento fiscal/comercial ya entregado, borrar el
rubro que lo originó no debería hacer desaparecer ese historial. En contra: a diferencia de
`importaciones_items` (registro de qué decía el Excel), acá `SET NULL` deja un certificado ya
**emitido** con una fila de avance que apunta a "nada" — capaz amerita un tratamiento distinto
(bloquear con aviso explícito en vez de dejar pasar en silencio), justamente porque hay un
documento fiscal de por medio. Al implementar esto, decidir con Seba antes de aplicar SET NULL a
ciegas.

### Sin acción de borrado, y NO alcanzables desde la app hoy (sin ruta de UI)

| FK | Referenciada por | Por qué no es explotable hoy |
|---|---|---|
| `apu_composicion_items.insumo_id` → `insumos(id)` | 0018 | Ningún archivo de `lib/` borra un insumo (`from('insumos').delete()` no aparece en ningún lado) |
| `obra_insumo_precios.corralon_id` → `corralones(id)` | 0030 | Ningún archivo de `lib/` borra un corralón |
| `modificaciones_obra.apu_privado_id` → `apu_composiciones(id)` | 0021 | Ningún archivo de `lib/` borra una composición completa (solo se editan ítems adentro) |
| `hitos_certificacion.hito_anterior_id` → `hitos_certificacion(id)` (auto-referencia) | 0006 | Modelo B es append-only, sin política DELETE |
| `escala_salarial_uocra.zona` / `obra_presupuesto_config.zona_uocra` → `zonas_uocra(codigo)` | 0045/0048 | Catálogo de zonas UOCRA, se administra a mano en SQL Editor, sin pantalla de borrado |
| Casi todas las FKs hacia `auth.users(id)` (`creado_por`, `emitido_por`, `confirmado_por_usuario_id`, etc. en la mayoría de las tablas) | Todo el proyecto | No existe ningún flujo de "borrar cuenta" en la app. Si alguna vez se agrega, cualquiera de estas se convierte en bloqueo — anotado para ese día, no accionable hoy |

Estas quedan como **candidatos latentes**, no bugs activos: el día que se construya una pantalla
para borrar un insumo, un corralón, una composición, o una cuenta de usuario, cualquiera de estas
FKs va a repetir exactamente el mismo síntoma que 0088/0093/#2. Vale la pena recordarlas cuando se
diseñe esa pantalla, no urgentes ahora.

### Verificado, ya corregido — sin acción pendiente

Las tres FKs de `rubros(id)` que sí importaban (`subitems.rubro_id`, `obra_subitems.rubro_id`,
`obra_rubros_orden.rubro_id`) tienen `on delete cascade`, y son consistentes entre sí (0016/0026/0028).

---

## Hallazgo menor — Hallazgo #6: fórmula de precio promedio duplicada

**Actualizado 2026-09-09** (al verificar el punto 2 del orden de ejecución del diagnóstico —
histórico de precios, ver `docs/diagnostico_general_producto.md` §3.5): no son dos copias, son
**cuatro**, y la gravedad sube de "baja" a "hay que resolverlas juntas si algún día `precios`
empieza a guardar historia" — ver el detalle completo en esa verificación. Las cuatro hacen
`avg(valor) from precios where insumo_id = X`, **sin filtro de fecha ni de fila más reciente por
corralón**:

- `calcular_precio_promedio_insumo` (0013) — función dedicada, sin uso en vivo hoy (solo queries de
  verificación dentro de otras migraciones).
- `calcular_composicion_detalle_subitem` (0072, última versión) — inline, 2 copias en el mismo
  archivo. La más importante: alimenta Factor K y `ComposicionApuScreen`.
- `calcular_precio_apu_subitems` (0090) — inline. Alimenta certificación vía
  `calcular_monto_obra_subitems`.
- `consolidado_insumos_obra` (0042) — inline. Alimenta Mat y MO.

Hoy no diverge porque `precios` nunca tiene más de una fila por (insumo, corralón) — cada
corrección de precio se hace con `UPDATE` en el lugar, nunca con un `INSERT` nuevo (ver
`docs/diagnostico_general_producto.md` §3.5 para el detalle completo de por qué). El día que eso
cambie, las cuatro empiezan a promediar precios viejos junto con el vigente si no se les agrega el
mismo filtro "una fila por corralón, la más reciente" en el mismo golpe — es exactamente el patrón
de "arreglar una copia y no las otras" que motivó todo este relevamiento.

**El criterio que falta, sin el cual lo de arriba no es viable — DECIDIDO 2026-09-09:**

- **El corralón cambió su precio real → fila nueva, con fecha nueva.** `INSERT into precios`, la
  fila vieja queda tal cual — es la serie histórica.
- **Corregimos un error nuestro, nunca fue un precio real → se corrige en el lugar.**
  `UPDATE precios SET valor = ...` sobre la fila existente, sin fila nueva. Ejemplos concretos:
  conversión de unidad mal hecha (el caso de la chapa en 0066, ML→M2), un error de tipeo al
  cargar, o el precio del paquete/bolsón cargado como si fuera el de la unidad de uso.

Sin esta distinción escrita en algún lado, la próxima limpieza de duplicados (el mismo patrón que
ya corrió dos veces, 0068 y 0083) no tiene manera de saber si dos filas para el mismo (insumo,
corralón) son historia real que hay que conservar o ruido de importación que hay que promediar y
borrar — y va a volver a borrar historia asumiendo lo segundo, sin poder distinguirlo.

---

## Qué se revisó y está bien conectado (no solo lo que está roto)

- **`tipo_presupuesto` / `aplica_impuestos`**: conectados de punta a punta y verificados en esta
  misma sesión (0090/0092 + refresco en vivo compartiendo un solo mecanismo).
- **Bloque completo de costo de mano de obra** en `obra_presupuesto_config` (14 columnas): todas
  escritas por los paneles correspondientes, todas leídas por `calcular_valor_hora_mano_obra`, sin
  ninguna huérfana.
- **`calcular_precio_final_apu_subitems` / `calcular_presupuesto_vivo_obra`**: única fuente para
  Cómputo, Solapa APU y dashboard — sin una segunda implementación de la cascada en ningún lado.
- **Vista previa vs. emisión de certificado** (`calcular_totales_certificado`,
  `calcular_excesos_certificado`, `emitir_certificado`): comparten la misma función, no hay
  divergencia entre lo que se previsualiza y lo que se congela — el criterio "no dupliques la
  cuenta en Dart" se siguió correctamente acá. El problema de fondo (Hallazgo #1) está en la fuente
  común, no en esta pieza.
- **`RubrosTab._cargarConteos`**: el contador "N de M tildados" por rubro se refresca al volver de
  `SubitemsScreen` — no es otra instancia del bug de refresco-en-vivo, ya está resuelto.
- **FKs de `rubros(id)`** (`subitems`, `obra_subitems`, `obra_rubros_orden`): las tres con cascade
  correcto y consistente entre sí.
- **`perfiles.es_pro`**: de solo lectura para el usuario a propósito, deuda técnica ya documentada
  y aceptada — no es un caso de "se guarda y nadie lee", es "no se puede escribir desde la app
  todavía", decisión distinta y ya conocida.

---

## Alcance de este relevamiento — qué quedó afuera

- No se revisó cada pantalla de `lib/presentation/` en detalle, solo las rutas de escritura/lectura
  de las tablas de configuración pedidas (`obra_presupuesto_config`, `obras`, `perfiles`) más las
  funciones de cálculo de precio. `obra_impuestos`, `obra_valor_hora_override`, `escala_salarial_
  uocra` y `zonas_uocra` se revisaron solo en la medida en que alimentan las funciones de precio.
- Gestión de Obra (documentación tipada, fotos, Gantt) y otras piezas ya anotadas como "no
  diseñadas todavía" en la memoria del proyecto no se revisaron — no aplica el patrón "dejó de
  estar sincronizado" a algo que nunca se construyó.
- No se corrió nada contra una base real — todo esto es lectura de `supabase/migrations/*.sql` y
  `lib/**/*.dart`, sin acceso a Supabase desde este entorno.
