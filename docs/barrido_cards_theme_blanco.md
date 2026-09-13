# Barrido de `Card` tras pasar el theme a blanco (2026-09-13)

**Qué cambió**: `cardTheme` en `lib/config/app_theme.dart` ahora declara `color: Colors.white` y
`surfaceTintColor: Colors.transparent`. Antes, el color de un `Card` sin `color:` propio lo ponía
Material 3 por defecto: `colorScheme.surfaceContainerLow`, derivado del `seedColor` azul del theme —
un lavanda muy claro. **Nunca fue una decisión de diseño, era un default heredado.**

**Para qué este barrido**: el riesgo del cambio es que en alguna pantalla ese lavanda estuviera
funcionando como separador sin que nadie lo hubiera decidido. Acá está el relevamiento, pantalla por
pantalla, **sin arreglar nada** — el reporte primero, las decisiones después.

---

## 1. El dato que ordena todo el resto

**Ninguna de las 21 pantallas con `Card` define su propio fondo.** Verificado buscando
`backgroundColor:` a nivel de `Scaffold` (no del `AppBar`, que es navy en casi todas y engaña) en las
21: cero resultados. Todas heredan `scaffoldBackgroundColor: 0xFFF4F6F8` del theme.

O sea: **el fondo de todas es F4F6F8**, un gris casi blanco — el mismo problema que tenía MIS OBRAS
antes de bajarlo a `E2E7EE`, que es la única pantalla que sobreescribe el suyo.

**Y ninguna tarjeta queda completamente plana**: el `cardTheme` define `elevation: 1.5`, así que hasta
la que no declara nada tiene esa sombra. El lavanda no era el único separador — era un separador
*extra* sobre una sombra que ya estaba, y es una sombra floja para ese fondo.

---

## 2. Las que NO se ven afectadas: declaran su propio color

El `color` de la instancia le gana al del theme, así que estas quedan exactamente como estaban:

| Pantalla | Tarjeta | Color propio |
| --- | --- | --- |
| `carga_avance_rubros_screen.dart` | resumen de arriba | `0xFFEAF1FB` (celeste) |
| `subitems_screen.dart` | partida aplicable | `0xFFEAF1FB` — **solo las tildadas**; las no aplicables pasan a blanco |
| `carga_avance_subitems_screen.dart` | partida al 100% | `0xFFF1F1F1` — **solo las completas**; el resto pasa a blanco |
| `revisar_importacion_screen.dart` | fila descartada | negro al 3% — **solo las descartadas**; el resto pasa a blanco |
| `cartel_firma_pendiente.dart` | el cartel | `amber.shade50` |
| `presupuestos_screen.dart` | proveedor | `blueGrey[50]` |
| `presupuestos_screen.dart`, `analisis_precios_tab.dart`, `mano_obra_tab.dart`, `proveedores_tab.dart`, `resumen_tab.dart` | la tarjeta-título de cada una | navy `0xFF1B365D` |

**Ojo con las tres condicionales** (`subitems`, `carga_avance_subitems`, `revisar_importacion`): usan
el color para **distinguir un estado** (tildada / completa / descartada) y el otro estado era el
lavanda. Al pasar a blanco, el contraste entre los dos estados **aumenta**, no baja. Es el único
lugar donde el cambio mejora algo por accidente.

---

## 3. Las que pasan a blanco puro sobre fondo F4F6F8 — lista de riesgo

Ordenadas por riesgo real, que no es "la tarjeta contra el fondo" sino **una tarjeta contra la de al
lado**: en una lista, dos tarjetas blancas pegadas con sombra 1.5 sobre un fondo casi blanco es
exactamente el "bloque continuo" de MIS OBRAS.

### 3.1 · Riesgo alto — listas de varias tarjetas iguales

| Pantalla | Separación propia | Nota |
| --- | --- | --- |
| `rubros_tab.dart` (Cómputo) | `elevation: 1`, margen 4px | **La más usada de la app.** Margen de 4px entre ítems: el más apretado de todos |
| `subitems_screen.dart` | `elevation: 1`, margen 4px | Mezcla tarjetas celestes (tildadas) y blancas |
| `carga_avance_subitems_screen.dart` | `elevation: 1`, margen 4px | Igual, mezcla con las grises del 100% |
| `apu_listado_tab.dart` | `elevation: 1`, margen 8px | |
| `gestion_obra_tab.dart` (historial de certificados) | `elevation: 2`, margen 12px | La mejor parada de las listas |
| `mat_y_mo_tab.dart` | sin elevación propia (1.5 del theme), margen 6px | |
| `miembros_obra_screen.dart` | sin elevación propia, margen 6px | 2 listas (miembros e invitaciones) |
| `adicionales_screen.dart` | sin elevación propia, margen 10px | |
| `quitas_demasias_screen.dart` | `elevation: 1`, margen 10px | |
| `composicion_apu_screen.dart` | `elevation: 1`, margen 8px | |
| `carga_avance_rubros_screen.dart` (lista de rubros) | `elevation: 1`, margen 4px | |
| `revisar_importacion_screen.dart` | sin elevación propia, margen 8px | Mezcla con las descartadas |

### 3.2 · Riesgo bajo — tarjeta única en la pantalla

No compiten con ninguna tarjeta vecina: solo tienen que despegarse del fondo, y para eso la sombra
del theme alcanza.

- `aceptar_invitacion_screen.dart` — la tarjeta del formulario.
- `invitar_miembro_screen.dart` — ídem.
- `cartel_costo_mano_obra.dart` — cartel informativo.
- `analisis_precios_tab.dart`, `mano_obra_tab.dart`, `proveedores_tab.dart`, `resumen_tab.dart` — la
  tarjeta de resultados de cada una, que va sola debajo de su tarjeta-título navy (y el contraste con
  el navy es enorme).

---

## 4. El caso puntual de `PresupuestoEstadoPanel` — no es lo que parecía

**No tiene ningún `Card`.** Las 5 apariciones que contaba el grep son llamadas a un helper privado
`_buildCard(...)` (`presupuesto_estado_panel.dart:566`) que construye un **`Container` con
`BoxDecoration`**, color explícito y borde propio:

| Estado del presupuesto | Color |
| --- | --- |
| Congelado | `green.shade50` + borde verde |
| Vencido | `amber.shade50` + borde ámbar |
| Presentado y vigente | `blue.shade50` + borde azul |
| Sin presentar | `grey.shade100` + borde gris |

**Y son ramas mutuamente excluyentes**: el `build` hace `if (congelado) return …; if (vencido) return
…; if (presentado) return …; return …`. **Se muestra una sola a la vez.** El miedo a cinco tarjetas
blancas fusionadas no aplica: ni son blancas, ni son cinco, ni están juntas. **El cambio de theme no
lo toca en nada.**

---

## 5. Recomendación, para cuando se decida

No hace falta tocar 12 pantallas. El patrón de la lista de riesgo es siempre el mismo, así que
convendría **un solo cambio en el theme, no doce en las pantallas**: subir la sombra del `cardTheme`
de `1.5` a una sombra navy al 10% con desplazamiento, como la que quedó en MIS OBRAS. Se hace en un
lugar, lo heredan las 21 pantallas, y las que declaran color propio también se benefician.

Lo que **no** recomiendo: oscurecer `scaffoldBackgroundColor` en el theme. En MIS OBRAS funcionó
porque es un listado sobre el que no se escribe; en pantallas de carga y formularios, un fondo más
oscuro empieza a pelear con los campos de texto y los diálogos.

Y **el margen de 4px de `rubros_tab`/`subitems_screen`** es un problema aparte, que ninguna sombra
arregla: 4px entre ítems es poco aire para una lista larga, y es la misma lección de la portada (el
aire es lo que agrupa). Ahí convendría mirar el margen antes que la sombra.
