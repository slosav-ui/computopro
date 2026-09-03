# Factor K (Solapa APU) — decisiones de diseño

Referencia: `docs/computopro_rubros_apu_spec.md` §1 (estructura de la hoja `APU` de
`PLANILLA_BASE_2_0_v3_CORREGIDA.ods`), memoria `bloque_factor_k_solapa_apu_diseno.md` (diseño
original, 2026-09-01) y `CLAUDE.md` "Vista sin materiales" (criterio de GG/EPP/Costo Financiero,
2026-09-03). Este documento consolida las decisiones tomadas al arrancar la implementación
(Paso A), no repite lo que ya está cerrado en esos otros archivos.

## 1. El bloque de cabecera no muestra montos — CERRADO

No existe un Costo-Costo único de la obra. Cada partida tiene el suyo (Mano de obra + Materiales +
Equipos de esa partida puntual) — la propia planilla lo estructura así, un resumen de 15 líneas por
partida, no uno por obra. Un "total general" que agregara todas las partidas cargadas sería otra
cosa (análogo al "Total General de la obra" que ya existe al pie de la hoja `RUBROS`, ver commit
`aecb2a6`), y además hoy no hay cómputo métrico conectado para calcularlo de todos modos.

Por eso el bloque de cabecera — que vive en `obra_presupuesto_config`, los 6 (7 en modo sin
materiales) porcentajes compartidos por toda la obra — muestra únicamente porcentaje y base
explicada en texto, nunca un monto. Los montos concretos ("Imprevistos — \$3.903") solo existen y
se muestran en el desglose de UNA partida puntual, pieza aparte (Paso B, más abajo).

**Consecuencia de diseño**: separar la pieza en dos capas. **Paso A** (esta ronda): el bloque de
configuración, sin depender de ningún dato que no exista todavía. **Paso B**, más grande, sin
empezar: el desglose de 15 líneas con montos reales de una partida puntual, que necesita conectar
`calcular_precio_apu_subitems` (`0034`, aplicada pero sin usar desde `lib/`) — y eso a su vez
depende de que exista cómputo métrico real (`obra_subitems` con cantidades cargadas), que hoy no
existe en ninguna obra: nada en `lib/` escribe ahí todavía. Separar así evitó que el Paso A quedara
bloqueado esperando una pieza mucho más grande.

## 2. Base de cada línea, en texto plano — CERRADO

Los 6 conceptos se aplican en cascada, cada uno sobre el acumulado del anterior — sin la base, un
monto aislado no se puede reconstruir y parece un error de cálculo (mismo problema que ya resolvió
el desglose de IERIC/FICS/FODECO del cartel de mano de obra, con un mecanismo distinto: ahí hay una
sola base rara que se normaliza; acá hay 5 bases encadenadas, y normalizarlas contra una sola habría
dejado paréntesis más largos que la propia cadena que pretenden aclarar).

Se optó por nombrar la base en texto plano en cada línea, traduciendo a palabras lo que la propia
planilla ya expresa en notación algebraica (columna C de la hoja `APU`: "D% X (4)+(4)", "E% X (6)",
etc.):

- Gastos Generales — X% sobre Costo-Costo
- Imprevistos — X% sobre Costo-Costo + GG
- EPP-Seguridad — X% sobre Costo-Costo + GG + Imprevistos
- Costo Financiero — X% sobre Costo-Costo + GG + Imprevistos + EPP
- Beneficio — X% sobre todo lo anterior

Estas 5 líneas **no cambian de texto entre los dos modos** (con/sin materiales) — el porcentaje y su
base son propiedades de la configuración, no de la vista activa. Lo que cambia con el monto real
(que solo existe a nivel de partida) es harina del Paso B, no de este bloque.

**Chequeo de cierre, criterio permanente**: Costo-Costo + los 6 conceptos tiene que dar exactamente
el Costo Total del Trabajo. Cuando exista la función que hace la cuenta real (Paso B), esto tiene
que ser una aserción — si no cierra, falla visible, no devuelve un número que no reconcilia. Mismo
criterio que el resto del proyecto viene aplicando (`calcular_precio_apu_subitems` nunca colapsa
"sin precio" a `0` en silencio).

## 3. Vista sin materiales, en el bloque de cabecera — CERRADO

Con el bloque sin montos, las tres líneas "fijas" (GG/EPP/Costo Financiero, ver `CLAUDE.md`) no
necesitan tratamiento especial de texto — siguen siendo la misma línea de la sección 2, en los dos
modos. Lo que sí cambia, solo visible con "Comp. Solo MO" activo:

- **Una 7ª línea**: "Gestión de materiales de terceros — X% sobre Materiales de la vista con
  materiales" (`gestion_materiales_terceros_pct`, ya en `obra_presupuesto_config` desde `0020`).
- **Una nota al pie**, estilo muted (mismo que ya usa el panel de mano de obra): *"Gastos Generales,
  EPP-Seguridad y Costo Financiero se aplican igual que en Materiales + Mano de obra — no dependen
  de quién compra los materiales."* Antepone la explicación antes de que el usuario llegue a ver el
  monto real en una partida (Paso B) y le parezca un error.

## 4. Gate de PRO en el botón "Editar", no al abrir el panel — CERRADO

Distinto del panel de cargas sociales de mano de obra (que se abre para cualquiera y gatea recién en
Guardar). La diferencia no es una inconsistencia: la regla general del proyecto es "no ocultar la
función, gatear la acción". El panel de cargas sociales **es** la única forma de que Free vea esos
parámetros — gatear su apertura le habría ocultado información a la que tiene derecho. Acá no: el
bloque de cabecera ya le muestra a Free los 6/7 conceptos completos, sin necesitar el panel. El
panel de edición no agrega ninguna información nueva, solo la capacidad de escribir — por eso el
gate va en el botón, consistente con la regla general, no en contra de ella.

El botón muestra el ícono PRO (`Icons.workspace_premium`, ámbar — mismo que ya usa el segmento
"Comp. Solo MO" del selector) para Free, calculado con el `esPro` que el bloque ya cargó al
montarse. El chequeo que decide si el guardado procede es en vivo, recién al tocar "Editar" — no se
reusa ese valor cargado para la decisión real, mismo principio que el resto de esta pieza (no
confiar en una foto vieja). Mientras responde esa consulta, el botón queda deshabilitado con texto
"Verificando..." — mismo patrón ya usado en los paneles de mano de obra.

## 5. El séptimo campo del panel de edición no se pisa — CERRADO

`PanelEditarFactorK` carga los 7 valores de `obra_presupuesto_config` en `initState`, sin importar
cuántos campos muestre — 7 controllers siempre, 6 o 7 `TextField` visibles según el modo activo.
Guardar manda siempre los 7 al repositorio (`actualizarFactorK`, sin campos opcionales ni
"parciales"): el que no se muestra nunca pierde su valor porque nadie lo tocó, no porque el método
lo "salte". Evita una lógica de actualización parcial en el repositorio que habría que mantener
sincronizada con qué campos decide mostrar la UI en cada momento. Mismo criterio que
`actualizarCargasSociales`: se editan y se guardan como un solo formulario.

## 6. El mock de la Solapa APU se elimina, no se oculta — CERRADO

`_buildTabApu()` en `presupuestos_screen.dart` tenía un ítem inventado ("02.01 Hormigón armado en
fundaciones", \$320.000, con materiales/mano de obra/equipos hardcodeados). Se elimina entero
(el ítem y los métodos `_buildApuSection`/`_buildApuDetailRow` que lo sostenían), no se oculta atrás
de un flag — mismo criterio ya aplicado cuando se conectó Rubros de verdad (se sacó la barra falsa
"SUBTOTAL CÓMPUTO DIRECTO \$0 · 0 Rubros" en vez de dejarla mostrando un número que no reflejaba
nada real). En su lugar, un estado vacío que describe la ausencia sin prometer un camino que no
existe: no hay ninguna pantalla hoy donde cargar cómputo métrico real.

## Pendiente — Paso B, sin empezar

Conectar el desglose de 15 líneas con montos reales de una partida puntual. Necesita, en orden:
cómputo métrico real (`obra_subitems` con cantidades, no existe ninguna fila hoy en ninguna obra),
después `calcular_precio_apu_subitems` para el Costo-Costo, y una función SQL nueva que aplique la
cascada completa de 6 conceptos (mismo criterio que `calcular_valor_hora_mano_obra`: la cuenta vive
en un solo lugar, no se duplica entre Dart y SQL, no puede desincronizarse).
