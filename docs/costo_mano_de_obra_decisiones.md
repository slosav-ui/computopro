# Costo de mano de obra: decisiones cerradas

Documento de referencia único para la pieza de costo de mano de obra (valor hora por categoría
UOCRA + cargas sociales, Solapa 3). Nace porque el fundamento de esta pieza venía quedando repartido
entre comentarios sueltos de migraciones y conversaciones que no dejan rastro escrito — leer este
archivo antes de retomar el tema, en vez de rediscutir algo que ya está resuelto.

Resumen ejecutivo en `CLAUDE.md`, sección "Costo de mano de obra: escala UOCRA y cargas sociales".
Schema real: `supabase/migrations/0036` a `0043`. Función: `calcular_valor_hora_mano_obra(obra_id,
fecha)`. Planilla de verificación propia: `docs/seed/costo_laboral_uocra.xlsx` (4 hojas: Parametros,
Escala UOCRA, Calculo, Resumen — fórmulas vivas, reproduce la liquidación real al centavo).

## 1. Alícuotas y su fuente

Todas las alícuotas de contribuciones patronales viven en `obra_presupuesto_config`, no en
`insumos` — son propias de cada empresa (ART depende de la póliza, SUSS depende de si tiene
certificado MiPyME, Fondo de Cese depende de la antigüedad del personal), no del catálogo
compartido de insumos.

| Concepto | Default | Fuente / fundamento | Editable por PRO |
|---|---|---|---|
| `suss_pct` | 18% | Ley 27.541 art. 19 — PyME/industria/construcción/agropecuario **con** certificado MiPyME vigente. Alternativa 20,4%: sin certificado MiPyME, o empresas de servicios/comercio por encima de mediana empresa tramo 2. | Sí |
| `obra_social_patronal_pct` | 6% | Ley 23.660, se calcula aparte del SUSS, sobre el bruto. | No (aplicada, no expuesta — ver §6) |
| `art_pct` | 10,23% | **Sin verificar.** Viene del PDF de la liquidadora ("VALOR OBRERO-092026", sept-26, no está en el repo), no de una póliza real. Pendiente abierto, ver §10. | Sí |
| `fondo_cese_pct` | 12% | Ley 22.250 art. 15, Decreto reglamentario 1342/81 — 12% el primer año, 8% desde el año de antigüedad. Se deja en 12% a propósito: con la rotación de obra, pocos operarios llegan al año. | Sí |
| `fics_pct` / `ieric_pct` / `fodeco_pct` | 2% / 1% / 1% | Art. 49 CCT 76/75 — se calculan **sobre el Fondo de Cese**, no sobre el sueldo. | No (aplicadas, no expuestas) |
| `uocra_empleador_pct` | 2% | Contribución patronal al sindicato. Tomada del PDF/planilla de la liquidadora igual que los fijos por operario — sin cita legal puntual verificada aparte de la existencia del concepto en el convenio. | No (aplicada, no expuesta) |
| `fijos_operario_mensual` | $57.344,78 | Suma de 5 componentes fijos del PDF de la liquidadora: ART fija $1.905 + Seguro de Vida Obligatorio $424,62 (Decreto 1567/74) + Preocupacional $23.333,33 + Indumentaria/EPP $29.681,83 + Telegramas/gestión $2.000. Los 5 verificados y coincidentes; el fijo de ART hereda el mismo pendiente que `art_pct`. | Sí (como un solo número, no desglosado — ver §10 de por qué) |

**Por qué "no editable pero aplicada" existe como categoría propia**: `obra_social_patronal_pct`,
`fics_pct`, `ieric_pct`, `fodeco_pct` y `uocra_empleador_pct` no admiten variación por empresa (son
alícuotas fijas por normativa/convenio), pero viven como columna igual — nunca como constante
hardcodeada en la función — para que una corrección de normativa se resuelva con un `UPDATE`, no
con un deploy.

### El 28% de la liquidadora — descartado, sin fundamento identificable

El PDF de la liquidadora trae una sola línea, idéntica en sus 5 hojas por categoría:

```
Seguridad social Jubilación+Obra social    28,00%  (Contribución Empleador)   17,00% (Aporte Obrero)
```

Comparado contra `suss_pct + obra_social_patronal_pct`: **18 + 6 = 24**, no 28. Probado contra la
alternativa de SUSS para empresas más grandes: **20,4 + 6 = 26,4**, tampoco. Ninguna combinación
conocida de las dos alícuotas normativas explica el 28% — sobra un punto y medio largo sin
identificar (posible adicional del régimen diferencial de la construcción, sin confirmar).

**Decisión (2026-09-02): se descarta el 28%, quedan 18/20,4 + 6 con fuente normativa citada.**
Sobre la remuneración mensual de un Ayudante ($1.271.424), la diferencia son ~$50.000/mes por
operario — no es un ajuste menor, pero adoptar un número sin poder explicarlo sería reemplazar un
supuesto por otro sin ninguna ganancia, y además rompería la única verificación al centavo que
existe hoy (`calcular_valor_hora_mano_obra` contra `docs/seed/costo_laboral_uocra.xlsx`). Queda
como pendiente externo — ver §10.

## 2. Categorías: por qué insumos y escala no calzan 1 a 1

Los 5 insumos oficiales de mano de obra (`0017_alter_insumos.sql`): OFICIAL ESPECIALIZADO, OFICIAL,
MEDIO OFICIAL, AYUDANTE, AYUDA DE GREMIO. Las 5 categorías de la escala (`0036`, códigos
`categoria_uocra`): AYUD, MOFI, OFIC, OFES, **SERE**. Coinciden 4 de 5 — a propósito, no es un dato
faltante:

- **Sereno (SERE)** es una categoría real del convenio (CCT 76/75), con básico propio y liquidación
  **mensual**, no por hora. Pero no participa de ninguna APU — nadie le pone rendimiento por m² a
  un sereno. Es costo indirecto de obra, entra por Gastos Generales cuando exista el bloque Factor
  K, no por este mecanismo. Por eso la escala lo carga (es parte de la normativa) pero hoy ningún
  insumo lo apunta.
- **Ayuda de Gremio** es un concepto de la APU (mano de obra que el contratista principal pone para
  asistir a un gremio subcontratado — abrir canaletas, acarrear, tapar después), sin básico propio
  en el convenio: no es una categoría escalafonaria. Se costea al valor del **Ayudante**
  (`insumos.categoria_uocra = 'AYUD'` para ambas filas).

**El vínculo insumo↔escala es por código (`categoria_uocra`), nunca por nombre** — un texto que hoy
coincide (`"OFICIAL"` = `"Oficial"`) puede divergir con un typo o un cambio de mayúsculas sin que
nada lo detecte; el código con `check` constraint sí lo impide.

## 3. Adicional de hormigón

`escala_salarial_uocra.adicional_hormigon_pct` = 15% sobre el jornal básico, uniforme para las 5
categorías (CCT 76/75). Corresponde **solo** al personal ocupado directamente en la colada, y
**solo** cuando no se usan medios mecánicos para elaborar, transportar, distribuir y vibrar el
hormigón — con hormigón elaborado y bombeado no corresponde.

**Nunca entra en el valor hora base** que calcula `calcular_valor_hora_mano_obra` — lo aplica la
APU de estructura como una decisión aparte, todavía sin construir. Que la app lo aplique por
defecto en las APU de estructura (para todos los usuarios, incluido Free — es lo que legalmente
corresponde ahí) es un supuesto de diseño sobre cómo trabaja la mayoría de las obras, no una
obligación legal; poder desactivarlo es función PRO. **Si algún día se suma en los dos lados a la
vez (valor hora base + APU de estructura), se cuenta dos veces** — eso sí sería un bug real, no una
decisión de diseño.

## 4. Constantes hardcodeadas en la función, y por qué no son columna

- **1/12 del SAC** (Ley 23.041): definición legal fija del aguinaldo, no una política de empresa —
  no varía, no necesita ser editable.
- **8 horas por jornal de referencia** (valuación de vacaciones para las 4 categorías por hora): no
  se mueve aunque el PRO cambie `horas_mensuales`, porque las vacaciones se pagan al jornal de
  convenio sin importar cuántas horas trabaje la empresa ese mes en particular.
- **25 días/mes** (conversión mensual→diario, solo en la rama de Sereno): el más arbitrario de los
  tres — hoy no afecta ningún número de la app porque Sereno no participa de ninguna APU. Revisar
  junto con el Factor K si alguna vez importa.

Las tres son aritmética/definición legal, no política de negocio variable — por eso viven como
literales en la función y no como columnas, a diferencia de `vacaciones_jornales_mes` (§5).

## 5. `vacaciones_jornales_mes` — por qué es editable por PRO, no una alícuota fija

Default 1 (`obra_presupuesto_config`, migración `0037`). 1 jornal/mes son 12 jornales/año, ~14
días — la licencia que corresponde con antigüedad **menor a 5 años** (Ley 20.744 art. 150). Con
personal de 5 a 10 años son 21 días y el valor pasa a 1,5; con más antigüedad, más.

No es una alícuota fija por normativa (como FICS/IERIC/FODECO): depende de la **antigüedad
promedio del personal de cada empresa**, que varía de una empresa a otra — mismo tipo de parámetro
que `horas_improductivas_mensuales`, que también quedó editable.

## 6. Tilde de cargas sociales (`aplica_cargas_sociales`)

Booleano en `obra_presupuesto_config`, default `true`, **de obra entera, no por categoría** — si
cada categoría pudiera estar en un modo distinto, el subtotal de mano de obra de una APU sumaría
peras con manzanas. Disponible para Free y PRO por igual.

- **Se caen** (modo `false`): todo el bloque de contribuciones patronales y `fijos_operario_mensual`
  — son costo de tener un operario registrado, que es justo lo que este modo saca.
- **Se mantiene**: el remunerativo completo, con SAC y vacaciones. Es salario, no carga patronal —
  el trabajador lo cobra igual, esté o no registrado.
- **`horas_productivas` no cambia entre modos.** Se sigue dividiendo por
  `horas_mensuales - horas_improductivas_mensuales` en los dos casos. El tilde es sobre cargas
  sociales, no sobre productividad — fusionar los dos conceptos haría que un solo interruptor
  moviera dos cosas distintas, y el número dejaría de ser explicable.

Con los defaults actuales, para Ayudante: `valor_hora` (con cargas) = $13.562,62,
`valor_hora_sin_cargas` = $8.881,54.

## 7. `obra_valor_hora_override`

El PRO puede fijar a mano el valor hora de una categoría puntual (tabla `0036`, columnas
`obra_id`/`categoria_uocra`/`valor_hora`/`usuario_id`/`created_at`/`updated_at`). Precedencia: si
existe override para una categoría, **gana siempre** sobre el cálculo automático.

**Tocar un parámetro de cargas sociales en `obra_presupuesto_config` no pisa ni recalcula un
override existente** — son mecanismos independientes, el override no se entera de que el cálculo
subyacente cambió. Borrado posible por categoría (`DELETE ... WHERE categoria_uocra = ...`) o todas
juntas (`DELETE ... WHERE obra_id = ...`, sin filtro de categoría) — no hace falta una función
aparte para ninguno de los dos casos, la RLS ya lo permite.

## 8. Los dos multiplicadores — no confundir uno con el otro

`calcular_valor_hora_mano_obra` devuelve dos ratios distintos, ninguno deriva del otro:

- **`multiplicador`** = `costo_mensual / remuneracion_mensual`. Contesta "¿por qué esto es tan
  caro?" contra el jornal pelado que dice el convenio — el número que un rubro tiene internalizado
  cuando ve $5.399 en la tabla de UOCRA y sabe que en realidad sale mucho más. Con los defaults
  actuales, Ayudante: **1,72×**.
- **`valor_hora / valor_hora_sin_cargas`**: cuánto se mueve el valor al destildar
  `aplica_cargas_sociales` — "¿cuánto más caro es formalizar a alguien pagándole lo mismo en mano?"
  (SAC y vacaciones quedan de los dos lados). Con los defaults actuales, Ayudante: **1,53×**.

Si en algún momento estos dos números coinciden, sospechar del cálculo — no es una coincidencia
esperable, son preguntas distintas con bases distintas (`remuneracion_mensual` vs. `remunerativo`).

## 9. Diferencias deliberadas contra el PDF de la liquidadora

La app **no tiene que reproducir** el valor hora del PDF de la liquidadora — hay tres motivos
identificados, todos deliberados:

1. El PDF incluye el adicional de hormigón en la base del valor hora; la app nunca lo hace (§3).
2. El PDF divide por 176 horas nominales de convenio; la app divide por **horas productivas**
   (`horas_mensuales - horas_improductivas_mensuales`), que descuenta feriados, enfermedades
   inculpables, licencias y paradas por clima.
3. El PDF suma los aportes del trabajador (17% + seguro de vida UOCRA) al costo — su línea se llama
   literalmente "Aportes y Contribuciones", mezclando ambos conceptos. Los aportes del trabajador
   se retienen del sueldo bruto, no son costo adicional del empleador — la app los excluye
   correctamente.

**El propio PDF no se valida contra sus totales declarados.** Al pie de cada hoja trae
`52,71% / 19,50% / $76.961,95`, con la nota impresa "Total Porcentaje 72,21% — **Varían las Bases
de cálculos**" — el documento mismo aclara que esos porcentajes no se aplican todos sobre la misma
base. Esos totales son **titulares, no una fórmula reproducible** — no sirven para validar el
documento de punta a punta; hay que validar línea por línea contra lo que cada concepto realmente
aplica (que es lo que se hizo en §1).

## 10. Pendientes abiertos, con dueño

| Pendiente | Estado | Quién lo resuelve |
|---|---|---|
| Alícuota real de ART (`art_pct`) y suma fija (`fijos_operario_mensual`) | 10,23% y $1.905 son de la liquidadora, no de la póliza propia del usuario | El usuario, contra su póliza |
| Composición del 28% de seguridad social | Descartada por falta de fundamento (§1) — no se va a seguir investigando salvo que aparezca una fuente nueva | El usuario, si le pregunta a la liquidadora |
| Certificado MiPyME de la obra propia de Seba | **No tiene certificado vigente** — en sus obras corresponde `suss_pct = 20,4`, no el default 18. Hay que editar el campo en sus obras reales. | El usuario, por obra |

## 11. Requisitos para el Paso 5 (UI — nada de esto implementado todavía)

- **BLOQUEANTE para repartir el APK — "volver al calculado" (borrar un `obra_valor_hora_override`)
  tiene que existir en la UI, no solo por SQL.** Desde que el lapicito de mano de obra escribe en
  `obra_valor_hora_override` (§13), fijar un valor a mano es un camino sin retorno para cualquiera
  sin acceso directo a la base: el diálogo de edición solo guarda, no hay ningún botón ni acción que
  borre el override y vuelva al valor calculado de la escala. Esto era una comodidad cuando la única
  vía de "fijar a mano" era `obra_insumo_precios` (que tampoco tiene "volver a automático" en la UI,
  pero un usuario podía cargar el mismo valor calculado a mano como workaround); para mano de obra,
  después de §13, no hay ningún workaround — la única salida real es un `DELETE` que solo Seba puede
  correr. No lo confundas con una mejora deseable: es la contraparte obligatoria de haber creado un
  mecanismo de escritura sin su mecanismo de borrado.
- **En el panel de edición del valor hora, lo primero y lo único visible tiene que ser el número
  editable — los parámetros de cargas van detrás de un link discreto tipo "¿de dónde sale este
  número?".** El usuario que solo quiere cambiar un número no tiene que entender ART ni Fondo de
  Cese para poder hacerlo. Decisión de layout, sin construir.
- **`suss_pct` no puede ser un número libre en la UI.** Un campo que dice "SUSS" no le dice nada a
  nadie. Tiene que ser una elección con nombre: *"Con certificado MiPyME — 18%"* / *"Sin certificado
  MiPyME — 20,4%"* — convierte una pregunta técnica en una que el usuario sabe contestar.
- **El cartel en modo "sin cargas" no puede mostrar el `multiplicador` que devuelve la función en
  ese modo** (cae a ~1,13, matemáticamente correcto pero no es lo que el usuario necesita ver ahí).
  Tiene que seguir mostrando el multiplicador **con cargas** (≈1,72×), con un texto tipo "con
  cargas sería 1,72×" — lo que el usuario quiere saber al destildar es cuánto se está ahorrando,
  no el ratio recalculado sobre la base más chica.
- **El control de `zona_uocra` tiene que ofrecer solo las zonas que existen en
  `escala_salarial_uocra`, nunca texto libre.** `zona_uocra` es `text` sin `check` ni FK a propósito
  (migración `0038`) — nada a nivel de base impide que una obra apunte a una zona sin escala
  cargada, y eso hace que `calcular_valor_hora_mano_obra` frene con `RAISE EXCEPTION` (ver §12, "RAISE
  EXCEPTION de zona faltante"). El control de UI es lo que
  vuelve esa excepción inalcanzable en uso normal — sin este requisito, la restricción de más abajo
  queda solo en el papel.
- **El panel de detalle de "Ayuda de Gremio" tiene que aclarar que se costea al valor hora del
  Ayudante.** Va a mostrar el mismo número que la fila "Ayudante" en dos cards separadas del
  consolidado (§2, §12) — sin esa aclaración, un usuario puede leerlo como un error de la app en vez
  de una decisión de diseño.
- Bloque plegable como primer elemento de la solapa APU (mismo patrón que el Factor K, ver
  `CLAUDE.md` § "Bloque Factor K en Solapa APU"), con el desglose línea por línea de este documento
  disponible para quien quiera verlo, no solo el número final.

**Pregunta abierta, no un requisito cerrado** (surgió al verificar el Paso 4 con datos reales de
prueba: un precio manual viejo de `AYUDANTE` daba $8.211 contra $13.562 calculado, ~40% abajo —
subcotizaría cualquier presupuesto real de esa obra). Hoy la marca "Cargado a mano" avisa que el
precio no se actualiza solo, pero no dice nada sobre si ese precio quedó desactualizado respecto al
cálculo automático. ¿Vale la pena señalar cuando un precio fijado a mano se aleja mucho del
calculado/automático (un `%` de diferencia, un ícono aparte, algo en el panel de detalle)? Evaluar
en el Paso 5, no diseñar ni implementar todavía.

## 12. Conexión al consolidado de Mat y MO (Paso 4) — CERRADO 2026-09-02

`consolidado_insumos_obra` (`0032`) extendida en `0041` — mismo `COALESCE` que ya resolvía
`obra_insumo_precios` vs. automático de corralones, con `calcular_valor_hora_mano_obra` sumada en
el medio de la cadena:

```
precio = coalesce(oip.precio, vh.valor_hora, p.promedio)
```

**Sin rama propia para mano de obra**: para materiales, `vh.valor_hora` nunca matchea (`insumos.categoria_uocra`
es `NULL`) y el `COALESCE` cae en `p.promedio` de siempre; para mano de obra, `p.promedio`
(`avg(precios.valor)`) siempre da `NULL` — un corralón no cotiza horas de oficial, ver `0034` — y el
`COALESCE` cae en `vh.valor_hora`. La
función de valor hora se llama **una sola vez** por consolidado (5 filas, no una por insumo) y se
hace `LEFT JOIN` por `categoria_uocra` — no hace falta consultar `obra_valor_hora_override` aparte,
`calcular_valor_hora_mano_obra` ya resuelve esa precedencia internamente.

**`AYUDA DE GREMIO` no se colapsa con `AYUDANTE`**: el `GROUP BY` agrupa por `insumo_id`, no por
`categoria_uocra` — son dos filas del consolidado, cada una con su propia cantidad, ambas con el
mismo `valor_hora` porque comparten categoría (§2). Verificado por construcción del `GROUP BY` y
verificado en el emulador (2026-09-02, obra de prueba): `OFICIAL ESPECIALIZADO` pasó de "Falta
cargar precio" a $18.424/hs sin marca (`origen='calculado'`), `AYUDANTE` y `OFICIAL` mostraron
precio con la marca "Cargado a mano" (tenían fila en `obra_insumo_precios`, gana sobre el
calculado), materiales sin ninguna alteración.

**`AYUDA DE GREMIO` no aparece hoy en el consolidado de ninguna obra — verificado contra el
catálogo sembrado, no es una obra puntual.** Grep sobre las 770 filas de `0023
_seed_apu_composiciones_rubros_2_17.sql`: 92 referencias a `AYUDANTE`, 90 a `OFICIAL`, 19 a
`OFICIAL ESPECIALIZADO`, 2 a `MEDIO OFICIAL` (partidas 16.3 y 16.4, único uso en todo el catálogo),
**0 a `AYUDA DE GREMIO`**. Ninguna de las 97 partidas oficiales la usa — no puede aparecer en el
consolidado de ninguna obra hasta que un PRO cree una composición propia que la referencie, tildes
lo que tildes en el catálogo oficial. Coherente con el diseño de §2 (concepto de composición propia,
no del catálogo oficial).

### Mapeo exhaustivo de `origen` — los 5 valores posibles, no solo la lista blanca del código

La UI colapsa `origen` a dos estados visuales (`InsumoConsolidadoObra.fijadoAMano`,
`lib/data/models/insumo_consolidado_obra.dart`) por lista blanca — **un valor nuevo que no se
agregue acá cae del lado "automático" por default**, así que si algún día se suma un origen que
representa algo puesto por el usuario, hay que sumarlo a la lista o va a quedar sin su marca sin
que nadie se entere. Tabla completa, para revisar de un vistazo el día que se agregue uno nuevo:

| `origen` | De dónde sale | Estado visual | ¿En la lista blanca (`fijadoAMano`)? |
|---|---|---|---|
| `'automatico'` | `avg(precios.valor)`, corralones — solo materiales | Automático, sin marca | No |
| `'calculado'` | `calcular_valor_hora_mano_obra`, sin override — solo mano de obra | Automático, sin marca | No |
| `'manual'` | `obra_insumo_precios.origen`, precio tipeado por el PRO para ese insumo puntual — **solo materiales desde `0042`**, ver §13 | Fijado a mano, badge "Cargado a mano" | Sí |
| `'presupuesto_firme'` | `obra_insumo_precios.origen`, precio real de un corralón — mecanismo todavía sin construir (roadmap "Mandar a Presupuestar"), el valor no puede existir hoy en ninguna fila — **solo materiales, nunca mano de obra por diseño (§13)** | Fijado a mano, badge "Cargado a mano" | Sí |
| `'override'` | `obra_valor_hora_override`, el PRO fijó a mano el valor hora de una categoría — único origen "fijado a mano" posible para mano de obra desde `0042` (§13) | Fijado a mano, badge "Cargado a mano" | Sí |

### `RAISE EXCEPTION` de zona faltante — propaga a todo el consolidado a propósito

Si `escala_salarial_uocra` no tiene fila para la `zona_uocra`/fecha de una obra,
`calcular_valor_hora_mano_obra` frena con `RAISE EXCEPTION` (`0039`). Llamada desde adentro de
`consolidado_insumos_obra`, esa excepción frena **todo** el consolidado — también las filas de
materiales, que no tienen nada que ver con UOCRA. Es a propósito, no un descuido de este paso: el
consolidado no atrapa la excepción ni la aísla. **Lo que la vuelve inalcanzable en uso normal es la
restricción del control de zona en el Paso 5 (§11)** — ofrecer solo zonas que existen en la escala,
nunca texto libre — no un `catch` acá. Hoy no puede pasar en la práctica (`zona_uocra` default
`'B'`, única zona cargada).

## 13. El lapicito de mano de obra escribe en `obra_valor_hora_override`, no en `obra_insumo_precios` — CERRADO 2026-09-02 (`0042`)

Encontrado al probar el Paso 4 en el emulador: coexistían dos mecanismos vivos para fijar a mano el
valor hora de un insumo de mano de obra, y no eran equivalentes.

- **`obra_insumo_precios`** (el mecanismo genérico, el que ya usa el lapicito para cualquier
  insumo) es **por insumo suelto**. Con dos insumos que comparten categoría (`AYUDANTE`/`AYUDA DE
  GREMIO`, §2), permitía dejar uno fijado y el otro en el calculado — dos números distintos para lo
  que es, por diseño, la misma categoría del convenio. No registra quién lo cargó ni cuándo.
- **`obra_valor_hora_override`** (`0036`) es **por categoría UOCRA**, construida específicamente
  para esto, con `usuario_id`/`created_at`/`updated_at`. La precedencia del `COALESCE` original
  (`oip.precio` antes que `vh.valor_hora`) hacía que el mecanismo genérico le ganara siempre al
  específico — la tabla construida para este propósito exacto quedaba tapada.

**Decisión: para los 5 insumos de mano de obra, el lapicito escribe en `obra_valor_hora_override`.
Un solo camino, por categoría, con trazabilidad. Para materiales, sin cambios.**

### El agujero no se cierra solo escribiendo distinto — hay que cerrarlo también donde se lee

Nada a nivel de base impedía (ni impide sin la constraint de más abajo) una fila de
`obra_insumo_precios` para un insumo de tipo `mano_obra` por otra vía — SQL directo, una fila
vieja sin limpiar. Si la única corrección hubiera sido "la UI ya no escribe ahí", esas filas
seguirían ganando. `0042` filtra el `JOIN` en `consolidado_insumos_obra`:

```sql
left join obra_insumo_precios oip
  on oip.obra_id = p_obra_id and oip.insumo_id = ins.id and ins.tipo != 'mano_obra'
```

Con esto, `oip` siempre es `NULL` para mano de obra — no hay ninguna vía, ni de UI ni de SQL
directo, por la que `obra_insumo_precios` vuelva a aplicar a un insumo de mano de obra. El
`COALESCE` queda efectivamente `coalesce(vh.valor_hora, p.promedio)` para esos insumos (y
`p.promedio` ya daba `NULL` siempre — §9, `0034`).

### Constraint nueva: todo insumo de mano de obra tiene que tener categoría

Sin esto, un insumo `mano_obra` con `categoria_uocra` en `NULL` (columna nullable, sin ninguna
restricción previa) hacía que el diálogo de edición no tuviera dónde escribir el override — y sin
un guard explícito en Dart, el código caía en el `else` genérico y escribía en
`obra_insumo_precios`, que este mismo cambio deja de leer para mano de obra. El usuario guardaría
sin ningún error visible y el número nunca cambiaría — exactamente el tipo de falla silenciosa que
esta pieza viene evitando en cada paso.

```sql
alter table insumos
  add constraint insumos_mano_obra_requiere_categoria check (
    tipo != 'mano_obra' or categoria_uocra is not null
  );
```

No se identificó ningún caso legítimo de un insumo de mano de obra sin categoría — conceptualmente
todo insumo de mano de obra representa una categoría UOCRA real, es la razón de ser de la columna.
Hoy no hay ningún código Dart que escriba en `insumos` (grep sin resultados, confirmado), así que
el estado inválido era teórico, no observado — la constraint lo vuelve imposible en vez de
"improbable". Si en algún momento aparece un caso real de mano de obra fuera de las 5 categorías
del convenio, esta constraint es lo primero que hay que revisar, no lo que hay que esquivar.

**En Dart, el mismo caso imposible falla visible en vez de escribir en el lugar equivocado**
(`mat_y_mo_tab.dart._mostrarDialogoEditarPrecio`): si un insumo de mano de obra llegara sin
`categoriaUocra`, se corta antes del `try` con un `SnackBar` de error — nunca cae en el `else` que
guarda en `obra_insumo_precios`.

### Texto del diálogo — corregido para no mentir

El texto original decía "este precio se usa en... que llevan `${insumo.nombre}`" — falso para mano
de obra desde que el valor es por categoría, no por insumo. El texto nuevo busca en la lista ya
cargada de insumos (`_insumos`, sin consulta extra) otros insumos que compartan `categoriaUocra`, y
si hay alguno los nombra explícitamente ("también corresponde a AYUDA DE GREMIO"), no dice
genéricamente "la categoría" — un nombre concreto es lo que el usuario puede verificar contra lo
que ve en pantalla.

### Datos existentes al momento del cambio — no migrados, no borrados

Verificado con una consulta cruzando las tres obras del proyecto: 3 filas de
`obra_insumo_precios` para insumos de mano de obra, las 3 en obras de prueba (`Obra de Prueba`:
`OFICIAL` $11.235 y `AYUDANTE` $8.210,57; `OBRA PRUEBA 3`: `AYUDANTE` $8.125) — ningún dato real en
juego. **Decisión: quedan tal cual, sin migrar a `obra_valor_hora_override` ni borrar.** Con el
filtro de más arriba ya quedan inertes — las tres obras vuelven a mostrar el valor calculado de la
escala (~$13.562 Ayudante, ~$15.822 Oficial), que es además lo que conviene ver mientras se sigue
probando el Paso 5.

### Consecuencia directa: "volver al calculado" pasa a bloqueante

Ver §11 — desde que el lapicito escribe en `obra_valor_hora_override`, fijar un valor a mano
es un camino sin retorno sin acceso directo a SQL. Ya no es una comodidad del Paso 5, es requisito
para repartir el APK.

## 14. Cartel de costo de mano de obra + tilde de cargas sociales (Paso 5, tanda 1) — CERRADO 2026-09-02 (`0043`)

Primera pieza de UI real de esta pieza — hasta acá todo era schema/función, sin ninguna pantalla.
Dos niveles decididos, solo el primero en esta tanda:

- **Nivel 1** (esta tanda): en la solapa Mat y MO, arriba de la sección "Mano de obra". Solo dos
  elementos — el cartel informativo y el tilde `aplica_cargas_sociales`. Nada de los 7 parámetros
  ahí: si van todos arriba de la solapa, el usuario abre Mat y MO y se encuentra con una pantalla
  de configuración contable en vez de con sus precios.
- **Nivel 2** (tanda siguiente, sin construir): los 7 parámetros, detrás del lapicito de cada fila
  de mano de obra — panel de edición del valor hora, no del cartel.

El tilde de impuestos y el selector de tipo de presupuesto **no se tocaron ni se mudan** — siguen
en el header de la Solapa APU (`selector_tipo_presupuesto.dart`). IVA/IIBB/tasas se aplican al
total del presupuesto (materiales + mano de obra por igual), no son parámetros del costo laboral.

### `valor_hora_con_cargas` / `multiplicador_con_cargas` — un tercer par de campos mode-independientes

`0043` (`DROP` + `CREATE`, cambia el `RETURNS TABLE`) agrega dos columnas a
`calcular_valor_hora_mano_obra`, siempre calculadas sin importar `aplica_cargas_sociales` —
simétricas a `valor_hora_sin_cargas`, que ya tenía esa propiedad:

- `valor_hora_con_cargas` = `costo_con_cargas / horas_productivas`.
- `multiplicador_con_cargas` = `costo_con_cargas / remuneracion_mensual`.

**Por qué hacían falta, no eran redundantes con lo que ya existía**: `valor_hora`/`multiplicador`
(los campos originales) son **dependientes del modo** — cuando `aplica_cargas_sociales = false`,
`multiplicador` cae de ~1,72 a ~1,13 (§11, ya documentado). El cartel necesita mostrar "1,72×"
**en los dos modos** (en modo sin cargas es la referencia contra la que se mide cuánto se está
ahorrando) — sin estos dos campos, Dart no podía reconstruir ese número: `horas_productivas` no se
expone, y sin ella no hay forma de derivar el "con cargas" a partir de lo demás. `v_costo_con_cargas`
ya se calculaba siempre dentro de la función desde `0039` (antes de la rama del toggle) — exponerlo
fue agregar dos asignaciones, no tocar ninguna lógica de cálculo existente.

`consolidado_insumos_obra` (`0041`/`0042`) usa `select *` sobre esta función en su CTE — agregar
columnas no la rompió, no hizo falta tocarla.

### Por qué `AYUD` es la categoría de referencia del cartel, y no un promedio ni la más usada en la obra

El cartel es uno solo para todo el bloque de mano de obra — no hay un cartel por categoría. El
multiplicador varía levemente entre categorías (verificado: 1,72 Ayudante/Medio Oficial, 1,71
Oficial/Oficial Especializado/Sereno, porque los fijos por operario pesan menos sobre una
remuneración más alta) — hacía falta elegir una.

**`AYUD` (Ayudante), fija, siempre la misma.** Dos alternativas descartadas, con motivo:

- **Promedio de las 5 categorías**: descartada porque es un número que no le corresponde a ninguna
  categoría real — si alguien pregunta de dónde sale, no hay una respuesta directa ("es Ayudante,
  la categoría más numerosa" sí la tiene).
- **La categoría con más `cantidad_total` en esa obra puntual**: descartada porque haría que el
  multiplicador del cartel se moviera solo cuando cambia el cómputo de la obra, sin que el usuario
  toque nada del cartel — un número que cambia sin causa visible es peor que uno levemente
  aproximado. Mismo defecto, aplicado a qué categoría describe el cartel en vez de a su valor, que
  motivó también descartar rotar la referencia por presencia de override (ver más abajo).

**Si la dispersión entre categorías se ampliara de forma material** (hoy 1,71-1,72, una diferencia
que no cambia la lectura del cartel), esta decisión hay que revisarla — la aproximación deja de ser
inocua si alguna categoría se aleja bastante del resto.

### El cartel y el override — aclaración acotada a `AYUD`, no a las 5 categorías

`valor_hora_con_cargas`/`multiplicador_con_cargas` ignoran cualquier `obra_valor_hora_override` a
propósito — describen el cálculo, no el número fijado a mano. Pero como el cartel toma `AYUD` como
referencia, si esa categoría específicamente tiene un override, el cartel muestra "aproximadamente
1,72×" mientras la fila de AYUDANTE en la grilla muestra el valor fijado a mano — dos números
distintos, uno al lado del otro, sin que nada lo explique.

**Se agrega una aclaración corta, en estilo secundario, solo cuando `AYUD.origen == 'override'`**:

> *El multiplicador corresponde al valor calculado por la escala. El de Ayudante está fijado a
> mano, así que no surge de este cálculo.*

**Por qué acotada a `AYUD` y no disparada por un override en cualquiera de las 5 categorías**: si
Oficial tiene un override, su propia fila ya lo dice con la marca "Cargado a mano" — no hay ninguna
confusión posible ahí, porque el cartel nunca afirmó describir a Oficial. Poner la aclaración
también en ese caso sería ruido sin información nueva, y el ruido hace que la gente deje de leer el
cartel cuando sí importa. El problema real es más angosto: es específicamente cuando la fila que el
cartel sí describe (`AYUD`) tiene un número distinto al que el cartel muestra arriba.

**Se descartó rotar la categoría de referencia a la primera de las 5 sin override** (alternativa
considerada) por el mismo motivo que ya descartó usar la de más `cantidad_total`: haría que el
cartel cambie qué categoría describe sin avisar, según un estado (haber cargado un override) que no
tiene ninguna relación visible con el cartel — reintroduce el mismo defecto en otro punto.

### Desglose del "Ver detalle" — 6 líneas, no 4

Ninguna alícuota va en texto duro — todas se leen de `obra_presupuesto_config` (7 columnas, de solo
lectura en esta tanda — el panel de edición es la tanda siguiente). Seis líneas, no las 4 que
agrupaban conceptos al principio del diseño:

1. Contribuciones patronales de seguridad social (`suss_pct`) — art. 19, Ley 27.541.
2. Obra social patronal (`obra_social_patronal_pct`) — Ley 23.660.
3. Fondo de Cese Laboral (`fondo_cese_pct`) — art. 15, Ley 22.250.
4. Seguro de riesgos del trabajo — ART (`art_pct`) — Ley 24.557.
5. Contribución patronal al sindicato — UOCRA (`uocra_empleador_pct`) — **sin cita legal puntual**,
   a propósito: solo la existencia del concepto en el convenio está verificada (§1), no un artículo
   específico. No inventar una cita que no se confirmó.
6. IERIC, FICS y FODECO — art. 49 del CCT. **Corregido tras verificar en el emulador (2026-09-02)**:
   mostrar el 4% crudo (`fics_pct + ieric_pct + fodeco_pct`) rompía el criterio de más abajo, porque
   ese 4% se aplica sobre el Fondo de Cese, no sobre el remunerativo como las otras 5 líneas — no
   era comparable ni sumable con ellas, aunque el texto dijera "sobre el Fondo de Cese". Se muestra
   el **impacto real sobre el remunerativo** (`fondo_cese_pct × (fics_pct + ieric_pct + fodeco_pct)
   / 100` = 12 × 4 / 100 = **0,48%** con los defaults) como número principal — el que sí suma —
   con el 4% original entre paréntesis para quien lo reconozca de una liquidación real: *"0,48%
   (equivale al 4% aplicado sobre el Fondo de Cese)"*.

**Criterio permanente, para revisar cada vez que se agregue o cambie una alícuota**: la suma de
las 6 líneas del desglose tiene que dar el **% total de contribuciones patronales sobre el
remunerativo** — el 48,71% que ya aparecía en `Parametros!C15` del xlsx propio y en §1 desde el
diagnóstico original de esta pieza, no un número nuevo. Verificado con los defaults: 18 (SUSS) + 6
(obra social) + 12 (Fondo de Cese) + 10,23 (ART) + 2 (UOCRA) + 0,48 (IERIC/FICS/FODECO, ya
convertido a % del remunerativo) = **48,71**. Confirmado también contra los valores reales de
Ayudante: `contribuciones / remunerativo` = 699.070,33 / 1.435.168 = 48,71%, coincide exacto.

**Corrección a una afirmación del usuario durante esta misma sesión, que no era exacta**: al pedir
este chequeo se dijo que la suma "tiene que dar el multiplicador que el cartel exhibe arriba"
(1,72×). **Eso no es correcto** — el multiplicador se calcula sobre la `remuneracion_mensual`
(el jornal de convenio, una base más chica que el remunerativo) y además suma
`fijos_operario_mensual`, que no es un porcentaje de nada. `(multiplicador_con_cargas - 1) × 100`
da ~72%, no 48,71% — son dos números distintos que responden preguntas distintas (ver §8, "Los dos
multiplicadores"). El chequeo real y verificable es contra el 48,71% de contribuciones sobre
remunerativo, no contra el multiplicador de la cabecera. **Si algún día la suma de las 6 líneas
deja de dar ese 48,71% (con los defaults actuales), es la señal de que el desglose quedó
incompleto o mal convertido de base — no ignorarlo como un redondeo.**

**Por qué SUSS y obra social patronal NO se unifican en una sola línea** (el diseño original las
agrupaba): tienen fundamento legal distinto, y sobre todo, **distinta editabilidad futura** — la
tanda 2 va a dejar que el usuario cambie SUSS entre 18% y 20,4% con el selector de MiPyME, mientras
que obra social patronal no se toca nunca. Si estuvieran fusionadas en un 24%, el día que el
usuario cambie a "sin MiPyME" y el desglose pase a mostrar 26,4%, no tendría forma de saber cuál de
los dos componentes se movió.

**"Ver detalle" queda disponible en los dos modos** (con cargas y sin cargas), decisión tomada acá
y no en el diseño original — en modo sin cargas, ver qué es lo que no se está pagando es
justamente lo más útil, no menos. El desglose en sí **no cambia entre modos**: siempre describe la
composición "con cargas", porque es la referencia fija, esté el toggle activo o no.

### "aproximadamente" en el texto de la cabecera

El texto original decía "Multiplicador aplicado: **1,72×**", sin calificarlo. Como el cartel
describe una sola categoría (`AYUD`) para las 5, un usuario que calcule a mano el multiplicador de
Oficial Especializado (1,71) y lo compare contra un "1,72×" presentado como cifra exacta podría
pensar que la app calcula mal. **"Multiplicador aplicado: aproximadamente 1,72×"** deja claro que
es un valor de referencia, no una afirmación puntual sobre las 5 categorías.

### Implementación

`ObraPresupuestoConfig`/`ObraPresupuestoConfigRepository` extendidos con `aplicaCargasSociales`
(editable, `actualizarAplicaCargasSociales`) + las 7 alícuotas (solo lectura). Modelo
`ValorHoraCategoria` + `ValorHoraManoObraRepository.getValorHoraPorCategoria` nuevos — devuelven
las 5 categorías siempre, no solo `AYUD`, porque la tanda 2 (panel de edición) las va a necesitar
todas. Widget `CartelCostoManoObra` (`lib/presentation/obra_detalle/tabs/cartel_costo_mano_obra.dart`),
autocontenido (mismo patrón que `SelectorTipoPresupuesto`), insertado en `mat_y_mo_tab.dart` arriba
de la sección "Mano de obra", solo cuando esa sección tiene filas. Recibe `onCambio`, llamado
después de guardar el tilde — el consolidado de `MatYMoTab` tiene que recargarse porque el valor de
mano de obra cambia con el modo.

### Pendiente anotado, sin acción — `multiplicador` (el campo viejo) miente cuando hay override

Encontrado al verificar en el emulador (2026-09-02), con el override de $7.500 puesto en `AYUD`:
`multiplicador` (el campo original de `0039`, no `multiplicador_con_cargas`) sigue dando 1,72 —
el valor calculado — en vez de reflejar el override (`7.500 / 1.271.424 ≈ 0,59`). La función aplica
el override solo a `valor_hora`, nunca a `multiplicador`.

**No se toca ahora** — el cartel usa `multiplicador_con_cargas` (que ignora el override a
propósito, es la referencia fija) y `valor_hora`/`origen` (que sí lo reflejan) para todo lo que
muestra, así que hoy nada consume el `multiplicador` viejo de una forma que este comportamiento
rompa. Pero es una columna real del contrato público de la función que hoy puede devolver un número
que no describe el valor efectivo de esa categoría — si algún consumidor futuro (la tanda 2, un
reporte, otra pantalla) lo usa sin saber esto, va a mostrar un multiplicador incorrecto en silencio
cuando haya un override activo. Revisar esta columna (¿debería reflejar el override, o
deprecarse en favor de derivarlo en el consumidor a partir de `valor_hora`/`remuneracion_mensual`?)
antes de que algo nuevo dependa de ella.

## 15. Panel de 7 parámetros + "Volver al calculado" (Paso 5, tanda 2) — CIERRA LA PIEZA — 2026-09-02

Última tanda del Paso 5. Con esto, la pieza completa de costo de mano de obra queda cerrada de
punta a punta: escala + cargas sociales (schema), función de cálculo, consolidado conectado,
cartel informativo, y ahora edición completa con salida.

### "Volver al calculado" — la fila es el camino principal, no el panel

Hasta esta tanda, fijar un valor a mano en `obra_valor_hora_override` no tenía salida sin SQL
directo — bloqueante para repartir el APK (§11, §13). Resuelto con `ObraInsumosRepository.
borrarValorHoraOverride` (`DELETE` por `obra_id` + `categoria_uocra`) expuesto en **dos lugares**:

1. **La propia fila del consolidado** (`mat_y_mo_tab.dart`, camino principal): cuando una fila de
   mano de obra tiene `origen == 'override'`, debajo del precio aparece "Valor UOCRA: \$X —
   Volver", tappable, sin diálogo de confirmación — el valor de destino ya está a la vista antes de
   tocarlo, esa es la decisión informada; un diálogo encima sería fricción redundante sobre algo
   que ya se decidió mostrar de antemano.
2. **El panel del lápiz** (`PanelValorHoraManoObra`), para quien ya abrió a editar y se arrepiente.

**Descartado un botón global "volver todo al calculado"** en el encabezado del bloque: el cartel ya
vive ahí, el bloque tiene pocas filas, y un botón que no dice de qué fila específica confunde más
de lo que ahorra — mismo criterio de "sin causa visible es peor que aproximado" que ya se usó para
descartar rotar la categoría de referencia del cartel (§14).

**El valor de destino es `valor_hora_con_cargas` o `valor_hora_sin_cargas` según el tilde vigente**
— verificado por la cadena de fórmulas de `0039`/`0043`, no asumido: si se borra el override,
`vh.valor_hora` cae a `costo_efectivo/horas_productivas`, que es exactamente uno de esos dos campos
según `aplica_cargas_sociales`. Ninguna columna nueva hacía falta.

### La desincronización encontrada al revisar el diseño — corregida antes de escribir código

Para saber cuál de los dos valores mostrar, la fila necesita el tilde `aplica_cargas_sociales` de
la obra — dato que hasta esta tanda solo cargaba `CartelCostoManoObra`, de forma independiente y
sin tocar (decisión explícita de no reabrir la tanda 1). La solución: `MatYMoTab._cargarConsolidado`
pasa a cargar **cuatro cosas juntas** — el consolidado, la config de la obra, el valor hora por
categoría (`Map<String, ValorHoraCategoria>`) y el estado PRO — en vez de solo el consolidado. Es
una copia independiente de la que ya mantiene el cartel (redundante, una lectura de una fila más
por carga de pantalla), a propósito para no tocar ese widget.

**El motivo de fondo**: `onCambio: _cargarConsolidado` ya era el callback que el cartel llama al
cambiar el tilde — como ahora ese mismo método recarga las cuatro cosas, destildar cargas sociales
actualiza la línea "Volver" de cada fila junto con los precios de la grilla, sin ningún código
nuevo de sincronización. Si `_cargarConsolidado` hubiera seguido recargando solo el consolidado, la
línea "Valor UOCRA" de una fila con override habría quedado mostrando el número del modo viejo
mientras el resto de la pantalla ya reflejaba el modo nuevo — exactamente el tipo de número que
queda mintiendo en un rincón que esta pieza viene evitando en cada paso. Verificado en el emulador
con el override de \$7.500 en AYUD: destildar cargas sociales actualiza la línea "Volver" junto con
los precios, no se queda en el número viejo.

### El panel — dos niveles, un solo "Guardar" para los 7 parámetros

`PanelValorHoraManoObra` (nuevo widget) reemplaza, solo para mano de obra, al diálogo genérico que
`mat_y_mo_tab.dart` sigue usando para materiales sin cambios. Estructura:

- **Arriba, lo único visible al abrir**: el campo de valor hora, mismo control y misma validación
  de siempre — el 90% de los casos de uso terminan acá.
- **Debajo, colapsado**: enlace "¿de dónde sale este número?" → despliega los 7 parámetros.
- **Los 7, con un solo botón "Guardar" al pie de esa sección** (no siete gates de PRO
  independientes) — Free puede escribir en los campos igual que cualquier otro control de esta app
  ("Free ve todo, no edita"), pero tocar "Guardar" muestra `mostrarDialogoFuncionPro` en vez de
  aplicar el cambio. Mismo patrón que `SelectorTipoPresupuesto`.
- **SUSS se presenta como elección con nombre**, nunca como el campo técnico: *"Con certificado
  MiPyME — 18%"* / *"Sin certificado MiPyME — 20,4%"* (`RadioListTile`, mapea a `suss_pct`). Los dos
  valores salen de §1, no están hardcodeados de nuevo — están en el código porque son literales de
  UI, pero coinciden con lo ya documentado ahí.
- **ART** tiene helper text explícito: *"Sacalo de tu póliza — el valor cargado es un supuesto de
  la liquidadora, no verificado"* — mismo pendiente de §1/§10, ahora visible en el momento en que
  alguien lo va a editar, no solo en un documento.
- **Fondo de Cese, horas mensuales, horas improductivas, vacaciones**: campos numéricos simples,
  sin texto de ayuda adicional — no se agregó guía no pedida para no ampliar el alcance de esta
  tanda.

### Selector de zona — texto fijo con una zona, selector real con más de una

Un solo componente (`_buildCampoZona`) lee `EscalaSalarialUocraRepository.getZonasDisponibles()` y
decide: si la lista tiene 1 elemento (hoy, `'B'`), se muestra como texto fijo, no como un
desplegable con una sola opción sin sentido de elegir; si tiene más de uno, se convierte solo en un
`DropdownButtonFormField` real. **El día que se cargue una segunda zona no hace falta tocar ningún
código acá** — el mismo componente ya sabe hacer las dos cosas según lo que lea. Sin esto, el
selector de zona sería el control que vuelve alcanzable el `RAISE EXCEPTION` de zona faltante
(§12) — con esto, sigue siendo inalcanzable en uso normal tal como estaba diseñado.

### `horas_mensuales > horas_improductivas_mensuales` — check nuevo, doble capa

Hallazgo real durante el diseño de esta tanda, no en la lista original: nada relacionaba
`horas_mensuales` con `horas_improductivas_mensuales` desde que existen (`0036`) — sin las dos
columnas nunca fueron editables desde la app, el problema era teórico. `calcular_valor_hora_mano_obra`
divide por `horas_mensuales - horas_improductivas_mensuales`; si un PRO carga
`horas_improductivas_mensuales >= horas_mensuales` desde este panel (primera vez que existe un
camino de escritura), ese divisor cae a cero o negativo — error de división o un valor hora
absurdo, sin ningún aviso.

**Doble capa, mismo criterio que `insumos_mano_obra_requiere_categoria` (0042)**:
- Dart valida al guardar (`PanelValorHoraManoObra._onGuardarParametros`), error inmediato e
  inline, antes de llegar a la base.
- `0044` agrega `check (horas_mensuales > horas_improductivas_mensuales)` en
  `obra_presupuesto_config`, como red de seguridad si la validación de Dart se saltea por
  cualquier motivo. Verificado antes de escribir la migración: ningún archivo de `lib/` leía ni
  escribía estas dos columnas hasta esta tanda (grep sin resultados) — las 3 obras existentes
  seguían en los defaults de `0036` (176 / 14,41), que cumplen el check.

### Ayuda de Gremio — mismo mecanismo de datos, reubicado

El panel reutiliza el mecanismo ya construido en la corrección anterior (§13): busca en
`todosLosInsumos` otro insumo de mano de obra con la misma `categoriaUocra`, y si lo encuentra, lo
nombra explícitamente en el texto — sin ningún nombre hardcodeado en el código. Con el catálogo
actual, esto es lo que hace que el panel de AYUDA DE GREMIO diga que comparte valor con AYUDANTE
(y viceversa), sin que el panel "sepa" que existe una categoría llamada así.

### Refactor: la bifurcación de mano de obra sale de `_mostrarDialogoEditarPrecio`

La rama de mano de obra que se agregó a ese diálogo genérico en la pieza anterior (§13) se retiró
por completo — ese diálogo vuelve a ser exclusivamente para materiales, tal como era antes de esa
pieza. Toda la lógica de mano de obra (guard de categoría nula, escritura del override, texto de
categoría compartida) se mudó a `PanelValorHoraManoObra`. Es refactor, no cambio de comportamiento
— verificado explícitamente en el emulador que el override sigue escribiendo en
`obra_valor_hora_override` y no en `obra_insumo_precios` después de la mudanza, no se dio por
bueno solo porque "no cambia el comportamiento".

### Implementación

Nuevos: `EscalaSalarialUocraRepository` (`getZonasDisponibles`), `PanelValorHoraManoObra`.
Extendidos: `ObraInsumosRepository.borrarValorHoraOverride`,
`ObraPresupuestoConfigRepository.actualizarCargasSociales` (las 7 columnas juntas, excepción
deliberada al patrón de una columna por método — se guardan como un solo formulario). `ObraPresupuestoConfig`
sumó `horasMensuales`/`horasImproductivasMensuales`/`vacacionesJornalesMes`/`zonaUocra` — hasta
esta tanda el modelo no los tenía, pese a que las columnas existían desde `0036`/`0037`/`0038`.

### Dos correcciones tras verificar en el emulador (`0045`)

**El link no puede llamarse "¿de dónde sale este número?"** — ese texto ya lo usa el "Ver detalle"
del cartel (§14), que explica sin editar nada. El de este panel edita siete parámetros reales.
Explicar es leer, editar es tocar — dos verbos distintos, dos nombres distintos, aunque estén a un
toque de distancia en la misma pantalla. Pasa a llamarse **"Ajustar cargas sociales"**.

**"Zona B" sola no le dice a nadie qué abarca** — se agrega `zonas_uocra`, tabla catálogo nueva
(`codigo`/`nombre`/`descripcion`), no una columna en `escala_salarial_uocra`. Motivo: la
descripción es un dato por zona, pero `escala_salarial_uocra` acumula una fila nueva por categoría
en cada paritaria (5 categorías × N vigencias, ver el diseño de `vigencia_desde`) — una columna ahí
repetiría el mismo texto 5 veces cada vez que se carga una escala nueva; la tabla aparte lo guarda
una sola vez por zona, se actualiza en un solo lugar. `escala_salarial_uocra.zona` suma una FK
hacia `zonas_uocra.codigo` — beneficio de integridad aparte (evita un typo de zona silencioso en
una futura carga), no lo que resuelve por sí solo la disciplina de "no cargar una zona sin escala"
(eso sigue siendo manual, `getZonasDisponibles()` sigue derivando la lista de `escala_salarial_uocra`,
nunca de `zonas_uocra` directamente — el catálogo describe, no habilita).

Solo se sembró **Zona B** (Neuquén, Río Negro y Chubut) — la única con escala cargada. Las otras 3
zonas reales del CCT 76/75 quedan documentadas en el comentario de `0045` para cuando se carguen,
no como dato vivo:

- **Zona A**: CABA y Buenos Aires, Santiago del Estero, Santa Fe, Mendoza, San Juan, Catamarca,
  Córdoba, Entre Ríos, Salta, Tucumán, Chaco, San Luis, Corrientes, La Rioja, Formosa, Jujuy y
  Misiones.
- **Zona C**: Santa Cruz.
- **Zona C Austral**: Tierra del Fuego.

**Pendiente sin resolver, no bloqueante**: La Pampa aparece en Zona A según algunas fuentes y en
Zona B según otras — no verificado contra el texto del CCT 76/75 en sí, solo contra notas de
terceros. No bloquea hoy (Zona B es la única cargada, y La Pampa no está en discusión ahí), pero
**hay que verificarlo contra el convenio real antes de cargar la escala de Zona A**, no antes.

En pantalla, la etiqueta de zona nunca es el código solo — siempre `nombre — descripcion` (ej.
"Zona B — Neuquén, Río Negro y Chubut"), con un texto de ayuda fijo debajo: **"La zona la determina
la provincia donde se ejecuta la obra, no dónde está la sede de la empresa"** — la regla real del
convenio, y el error más común si no se aclara.

### PENDIENTE CRÍTICO — cargar el resto de las zonas es requisito para salir de Neuquén/Río Negro/Chubut, no una mejora

Con una sola zona cargada, `zona_uocra` nace en `'B'` para toda obra nueva (default de la columna,
`0038`) y el selector se muestra como texto fijo — correcto y deliberado mientras solo exista Zona
B (§15, más arriba). Pero eso tiene una consecuencia real que no es evidente mirando el código: **un
usuario de cualquier provincia fuera de Neuquén/Río Negro/Chubut hoy calcularía sus obras con la
escala de Zona B, sin ningún aviso y sin poder corregirlo** — el selector no aparece mientras haya
una sola zona, así que no hay ni siquiera un lugar donde notar el error. La diferencia entre Zona A
y Zona B en la escala UOCRA es del orden de 15-20% — no es un margen de error menor.

**Cargar las escalas de Zona A, Zona C y Zona C Austral es requisito para repartir la app fuera de
esa región, no una mejora futura opcional.** Lo que hace falta ese día:

1. Básicos reales de las 3 zonas en `escala_salarial_uocra`, con sus filas correspondientes en
   `zonas_uocra` — fuente: el texto del CCT 76/75 o una circular oficial de UOCRA, **nunca**
   resúmenes de terceros (se encontraron sitios con zonificaciones publicadas incorrectas al
   armar esta lista).
2. Resolver dónde ubica el convenio a **La Pampa** (Zona A según algunas fuentes, Zona B según
   otras) — sigue sin resolver, ver nota de arriba.
3. **Revisar el default de `zona_uocra` ('B') una vez que haya más de una zona cargada.** Un
   default silencioso deja de ser aceptable con varias zonas reales compitiendo — las opciones son
   preguntar la zona al crear la obra, o derivarla de la provincia si la obra ya la tiene cargada
   como dato. Sin decidir todavía cuál.
4. El selector de zona del panel **se activa solo**, sin tocar ningún código — `_buildCampoZona`
   ya lee la cantidad de zonas disponibles y elige entre texto fijo y `DropdownButtonFormField`
   automáticamente (§15). Lo único que falta ese día es el dato, no la UI.

**Actualización (`0048`) — ver §17.** El punto 3 quedó decidido (gate condicional en el alta de
obra, sin escribir todavía porque hoy es imposible de verificar en el emulador) y la zona salió del
gate de PRO. Sigue sin resolver: los básicos reales de las 3 zonas (punto 1) y la verificación de
La Pampa contra el texto del convenio (punto 2) — §17 solo carga el catálogo descriptivo, no
escala.

Las 4 zonas reales del CCT 76/75, para cuando se retome:

| Zona | Provincias |
|---|---|
| A | CABA, Buenos Aires, Santiago del Estero, Santa Fe, Mendoza, San Juan, Catamarca, Córdoba, Entre Ríos, Salta, Tucumán, Chaco, San Luis, Corrientes, La Rioja, Formosa, Jujuy, Misiones |
| B | Neuquén, Río Negro, Chubut |
| C | Santa Cruz |
| C Austral | Tierra del Fuego |

### Bug real encontrado en la verificación — el gate de PRO no mostraba el diálogo

Con `es_pro = false` confirmado por SQL, tocar "Guardar parámetros" no mostraba
`mostrarDialogoFuncionPro` — el panel se cerraba directamente, como si hubiera guardado. Revisado
el código línea por línea: la lógica en sí (chequeo antes de cualquier guardado, `return` antes de
llegar al `Navigator.pop`) era correcta. **La causa real era el dato, no la lógica**: el panel
recibía `esPro` como parámetro del constructor, una foto tomada por `MatYMoTab` la última vez que
cargó — si la pestaña no se había recargado entera después del `UPDATE` de `es_pro` en la base
(por ejemplo, abrir el panel sobre una pantalla que ya estaba abierta de antes), esa foto quedaba
vieja sin que ningún error de código lo delatara.

**Corregido dejando de confiar en la foto**: `_onGuardarParametros` ahora llama a
`PerfilRepository.esPro(usuarioId)` **en el momento de tocar "Guardar parámetros"**, no antes —
verificación en vivo contra la base, no contra un estado cargado quién sabe cuándo. El parámetro
`esPro` del constructor de `PanelValorHoraManoObra` se sacó por completo (junto con `_esPro`/
`PerfilRepository` en `MatYMoTab`, que ya no los necesita para nada más) — dejarlo ahí, sin uso,
habría sido el mismo tipo de trampa: un campo que aparenta ser el gate y ya no lo es, esperando que
alguien lo reconecte mal en el futuro.

**Los dos comportamientos que pedía la verificación ya quedan cubiertos por esta misma
corrección, no hacen falta cambios aparte**: el diálogo de función PRO aparece antes de que se
intente guardar nada (el `return` corta el flujo inmediatamente después de mostrarlo), y el panel
nunca llega a `Navigator.pop` cuando el guardado no se produjo — los campos tipeados por el usuario
quedan intactos, visibles, listos para que lea el diálogo y entienda qué pasó.

**CORRECCIÓN, esto de arriba estaba mal diagnosticado — ver la sección siguiente.** El gate de PRO
nunca tuvo el bug: la verificación en vivo funcionaba desde el principio. El problema real era otro
por completo, y esta "corrección" no lo tocaba — quedó como registro del camino equivocado, no
como la explicación real.

### El verdadero problema: el botón de guardar los parámetros vivía debajo del scroll — y, peor, dos botones "Guardar" con alcance distinto

Verificado con una app reiniciada de cero (para eliminar la duda de hot reload) y scrolleando el
panel hasta el final: **"Guardar parámetros de la obra" estaba ahí, y el gate de PRO funcionaba
perfecto** cuando se llegaba a tocarlo. El bug real no era el gate — era que el botón quedaba fuera
de vista sin ninguna señal de que había más contenido abajo, y mientras tanto existía un segundo
botón "Guardar" (el del valor hora, al pie fijo del diálogo, el lugar donde cualquiera espera
encontrar el botón de guardar) que **hacía algo completamente distinto y no lo decía**. El usuario
que editaba ART y tocaba el "Guardar" visible se iba convencido de haber guardado, sin haber
guardado nada — el mismo síntoma que se atribuyó al gate de PRO en la ronda anterior, pero por una
causa completamente distinta.

**Decisión: un solo botón "Guardar", al pie del diálogo, que guarda lo que corresponda de cada
mitad según lo que el usuario haya tocado** — el usuario no tiene por qué saber que por debajo hay
dos tablas distintas, eso es organización interna, no algo que la pantalla deba exponer.

### Cómo se decide "qué tocó el usuario" — dos criterios distintos, uno para cada mitad

No es el mismo método para las dos partes, porque equivocarse tiene consecuencias distintas en
cada una:

- **Valor hora**: comparación **numérica** contra el valor precargado, con tolerancia para
  redondeo. Acá "guardar de más" tiene un costo real — si se guardara sin que el usuario haya
  cambiado nada, cualquiera que abra el panel solo para mirar los parámetros saldría con un
  override creado a traición, convirtiendo una categoría `calculado` en `override` sin haberlo
  pedido. Eso rompería directamente "Volver al calculado" (§15, más arriba). Por eso acá sí importa
  distinguir "cambió" de "no cambió".
- **Parámetros (los 7)**: comparación de **texto crudo** de cada `TextEditingController` contra el
  texto con el que se inicializó (`_artTextoInicial`, etc. — un snapshot guardado en `initState`,
  no un número recalculado), más el booleano de MiPyME y el código de zona contra sus propios
  snapshots iniciales. Nunca se comparan números parseados acá — comparar strings esquiva del todo
  el problema de redondeo (si el usuario no tipeó nada, el string es idéntico byte a byte al que se
  cargó). Guardar los mismos 7 valores de nuevo no tiene ningún efecto colateral (a diferencia del
  valor hora), así que acá el sesgo hacia "guardar de más" no cuesta nada.

**Primera versión de este criterio, con un falso positivo real encontrado en la verificación**: la
condición inicial era solo "la sección se abrió alguna vez" (`_seccionParametrosAbierta`). Un
usuario Free que abre "Ajustar cargas sociales" únicamente para mirar de dónde sale el número —el
uso más común de ese link, es literalmente para lo que existe— y toca "Guardar" sin cambiar nada,
salía con el cartel de función PRO reprochándole algo que no hizo, y el panel quedaba trabado.
**Corregido**: `_parametrosTocados` exige `_seccionParametrosAbierta && _parametrosCambiaron` — la
bandera de apertura sigue existiendo (sigue siendo necesaria: sin haber abierto la sección no hay
nada que comparar), pero ya no alcanza sola.

### El cierre del panel — regla final, con la corrección del caso "abrí para mirar, no toqué nada"

El panel **cierra normal** cuando no había nada que guardar (`huboIntento == false`) — abrir para
mirar y salir por "Guardar" es un uso legítimo, no un error, y no amerita ningún mensaje. **Queda
abierto únicamente cuando algo se intentó y no se pudo** — validación inválida en cualquiera de las
dos mitades, o bloqueado por PRO. El mensaje del cartel de función PRO está gateado por
`huboGuardadoValorHora` (si esa mitad realmente se guardó), no por `valorHoraCambio` (si solo se
intentó) — si el valor hora era inválido y no llegó a guardarse, el cartel no puede decir que se
guardó.

### El campo de valor hora vacío

Si el usuario borra el campo y lo deja vacío, no se interpreta como "volver al calculado" (para eso
ya existe el link "Volver", visible cuando hay override) — se trata como un intento inválido:
aviso inline ("Vacío no se guarda — para volver al valor calculado usá 'Volver' arriba") y esa
mitad no se guarda, sin bloquear que la mitad de parámetros sí se guarde si corresponde.

### El `Scrollbar`

`content` pasa de `SingleChildScrollView` solo a `Scrollbar(thumbVisibility: true, child:
SingleChildScrollView(...))` — barra de scroll siempre visible, no solo mientras se arrastra. Con
el botón ya afuera del área que scrollea esto no es indispensable para ese caso puntual, pero el
problema de fondo (contenido largo sin ninguna señal de que hay más) sigue existiendo para
cualquier campo de la sección expandida, así que se deja la señal general.

### Verificado en el emulador — los 7 casos, todos correctos

Abrir y cerrar sin tocar nada (cierra limpio), solo valor hora, solo parámetros con Free (cartel,
panel abierto), los dos juntos con Free (guarda el valor hora, avisa de los parámetros, cierra),
los dos juntos con PRO (guarda todo sin cartel), vaciar el valor hora (aviso inline, panel
abierto), y el `Scrollbar` visible sin arrastrar. Confirmado además en la grilla que el valor hora
del caso 4 quedó realmente guardado, no solo que el panel cerró.

**Los logs ya cumplieron su función y se sacaron** — el flujo unificado quedó verificado con los 7
casos reales, no hace falta seguir instrumentado.

### Dos correcciones más, encontradas en esa misma verificación

**"Volver" duplicado.** Con una categoría con override, "Valor UOCRA: \$X — Volver" aparecía dos
veces: en la fila del consolidado (el camino principal, decidido en §15 más arriba) y de nuevo
adentro del panel, debajo del valor hora. Se sacó del panel — `_onVolverAlCalculado`,
`_valorSiSeBorraElOverride`, `_fmtMoneda` y el estado `_volviendoAlCalculado` se eliminaron enteros
del archivo, no solo se ocultó el widget. El panel ya no tiene ningún mecanismo de "volver" propio;
el único camino es la fila.

**Los 7 parámetros no tenían forma de saber cuál era su valor original.** Mismo problema que ya se
había resuelto para el valor hora (con "Volver"), sin resolver para los parámetros. La solución acá
es distinta a propósito: **no un botón que revierta**, sino mostrar el valor por defecto en el
propio label de cada campo — `"ART (%) — por defecto 10,23"`. Se descartó un botón de "restaurar
los 7" porque revertiría de golpe ajustes que el usuario sí quería conservar; son campos
independientes, no una unidad.

**Distinción conceptual deliberada en el texto**: nunca dice "valor correcto", siempre "por
defecto". El "Volver" del valor hora tiene un destino con autoridad real — la escala UOCRA, una
fuente normativa. Los parámetros no: el 10,23 de ART es el supuesto que trajo la planilla de la
liquidadora, marcado como pendiente de reemplazar por la póliza real (§1, §10) — llamarlo "correcto"
sería mentir sobre su procedencia. Aplicado a los 7: ART, Fondo de Cese, horas mensuales, horas
improductivas, vacaciones (los 5 campos de texto), el selector de MiPyME ("Por defecto: con/sin
certificado MiPyME"), y la zona (en el label del selector, solo relevante el día que haya más de una
zona — con una sola no hay nada que "por defecto" pueda comunicar que el texto fijo no diga ya).

**Corrección post-verificación**: el párrafo anterior decía que el "por defecto" salía "de la
columna real de la base" — falso. En esta implementación sale de `widget.config`, que es la
configuración ACTUAL de la obra, no el default de la columna. Para una obra donde alguien ya había
cambiado el ART a 10,30, la etiqueta decía "por defecto 10,30" en vez de 10,23. Bug real, encontrado
por el usuario en la verificación en emulador, no por revisión de código. Queda anotado y sin
arreglar a propósito en §16 (la separación en dos ventanas iba primero, para no reescribir el mismo
archivo dos veces) — el arreglo real (constantes Dart, no una función de catálogo de Postgres,
descartada por desproporcionada) es el paso siguiente después de §16.

## 16. Separación en dos ventanas — CIERRA LA TANDA 2 DE VERDAD — 2026-09-02

### El diagnóstico: dos cosas de naturaleza distinta convivían en un solo diálogo

El panel mezclaba fijar el valor hora de una categoría (acción rápida y frecuente) con ajustar los
7 parámetros de cargas de toda la obra (configuración, se toca una vez). Los rótulos de alcance
("solo esta categoría" / "toda la obra") separaban el significado, pero no la interacción: el campo
editable de valor hora —el que crea un `obra_valor_hora_override` si se toca por error— quedaba
visible arriba todo el tiempo, incluso cuando el usuario solo había venido a cambiar el ART.

Esa convivencia, no cualquiera de sus síntomas puntuales, fue la causa de fondo de las cuatro rondas
de correcciones de esta tanda: los dos botones "Guardar" ambiguos, el botón de parámetros escondido
debajo del scroll, el falso positivo de la bandera de "sección abierta" para un Free que solo mira,
y el botón único que terminó resolviendo todo eso con una máquina de estados no trivial (`_onGuardar`
único, `_parametrosTocados`, comparación de textos crudos, mensaje combinado de PRO). Todos son
síntomas de la misma causa, no problemas independientes.

### La decisión: dos ventanas, cada una con un solo alcance

**Ventana 1** (`PanelValorHoraManoObra`, el lapicito) — solo el valor hora de la categoría. Campo,
link "Ajustar cargas sociales", Cancelar, Guardar. Nada más.

**Ventana 2** (`PanelParametrosCargasSociales`, nuevo archivo) — se abre desde el link, encima de la
primera. Solo los 7 parámetros. El campo de valor hora no aparece acá. Cancelar y Guardar propios.

Descartado llevar los parámetros a los controles de la obra: mantiene el camino que el usuario ya
conoce (el lapicito de la fila) y es menos trabajo — la separación en dos ventanas ya resuelve el
problema de fondo sin necesitar ese cambio de ubicación.

### Lo que esto elimina de raíz — no se migra, se borra

Con cada ventana teniendo un solo Guardar de un solo alcance, toda la máquina de estados armada para
el botón único dejó de tener trabajo que hacer:

- `_seccionParametrosAbierta` y la comparación de textos crudos contra un snapshot inicial — Guardar
  en la ventana 2 siempre guarda los 7, no hace falta detectar "qué cambió".
- El falso positivo del Free que solo mira — desaparece porque Cancelar es la salida natural, nunca
  dispara el gate de PRO.
- "Cierro solo si algo se guardó" — cada ventana cierra con su propio Guardar o Cancelar, sin un
  caso combinado que resolver.
- El mensaje combinado de PRO ("se guardó el valor hora, los parámetros no") — ya no existe el caso
  mixto: el gate vive solo en la ventana 2, un único mensaje.

Se mantiene tal cual: el gate de PRO en vivo (verificado recién al guardar, nunca antes), la
validación de horas improductivas < horas mensuales (mismo check que `0044`), el `Scrollbar` de la
ventana 2 (sigue teniendo 7 campos), "Volver al calculado" solo en la fila del consolidado (en
ninguna de las dos ventanas), y el bug del "por defecto" de más arriba — deliberadamente sin tocar
en este cambio.

### Caso 1 — la ventana 1 se queda abajo cuando se guardan los parámetros

El valor hora que muestra el campo de la ventana 1 puede quedar desactualizado si los parámetros que
lo calculan cambiaron en la ventana 2. Se evaluaron tres caminos: refrescar el campo automáticamente
(exige distinguir si el usuario ya lo había tocado, para no pisarle un valor tipeado — reintroduce la
misma clase de rama condicional que esta separación busca eliminar), cerrar la ventana 1 también
(tira un valor hora sin guardar si el usuario tenía algo tipeado), o avisar sin tocar nada. Se eligió
la tercera: `_huboGuardadoDeParametros` se pone en `true` cuando la ventana 2 devuelve `true`, y se
muestra una nota fija ("Los parámetros de cargas cambiaron. Cerrá y volvé a abrir para ver el valor
recalculado.") sin recalcular ni cerrar nada. Es la opción honesta — nunca afirma un número como
vigente cuando puede no serlo — y no agrega ninguna rama nueva de "¿estaba tocado o no?". La bandera
viaja incluso si el usuario después cancela la ventana 1: si los parámetros se guardaron, el panel
tiene que devolver `true` para que `MatYMoTab` recargue el consolidado, sin importar qué pasó con el
valor hora.

Se evaluó además si la nota podía mostrar el valor recalculado en vez de solo avisar — no sale
gratis: la ventana 1 nunca tuvo el config nuevo (ver Caso 2), y pedirlo solo para esa nota es el
mismo round-trip que se descartó al elegir la opción "avisar". Queda la nota genérica.

### Caso 2 — la config queda vieja si se reabre la ventana 2 sin cerrar la ventana 1

La ventana 2 recibía `config` por constructor, pasado desde la ventana 1, que a su vez lo recibía de
`MatYMoTab` en el momento de abrir el lapicito. Si el usuario guardaba parámetros y volvía a abrir
"Ajustar cargas sociales" sin cerrar la ventana 1, la ventana 2 nueva se construía con el mismo
`config` de antes de guardar — mostraba los valores viejos, y guardar de nuevo desde ahí pisaba el
cambio recién hecho (la ventana 2 guarda siempre los 7 sin comparar, a propósito — ver más arriba —
y ese mismo criterio se vuelve en contra si el dato de partida está desactualizado).

Se resolvió sacando `config` del constructor: `PanelParametrosCargasSociales` ahora recibe solo
`obraId` y hace su propio `_cargarConfig()` (`ObraPresupuestoConfigRepository.getConfig`) al abrirse.
Mismo principio que el gate de PRO en vivo — no confiar en una foto que alguien más pasó, pedir el
dato en el momento en que importa. Elimina la clase de bug entera en vez de exigir que la ventana 1
se acuerde de refrescar y repasar el dato correcto en cada apertura siguiente.

Consecuencia: la ventana 1 (`PanelValorHoraManoObra`) ya no necesita `config` para nada — solo lo
reenviaba. Se sacó también de su constructor, y de la llamada en `mat_y_mo_tab.dart`
(`_onTocarLapiz`) que la construye.

Detalle de implementación: como el config ahora se carga async, los 5 `TextEditingController` de la
ventana 2 pasan a nullable y se crean recién dentro de `_cargarConfig` cuando llega el dato (antes
que eso, `build()` muestra un `CircularProgressIndicator`). `_cargarConfig` hace `dispose()` de los
controllers anteriores antes de crear los nuevos — defensivo: hoy se llama una sola vez desde
`initState`, pero si en el futuro se agrega una forma de recargar, evita una fuga silenciosa de
controllers sin `dispose`.

### Verificado en el emulador — confirmado

Los 14 casos de la lista de verificación pasaron, incluido el caso puntual que motivó el Caso 2:
guardar en la ventana 2, reabrirla sin cerrar la ventana 1, confirmar que muestra los valores
recién guardados. Commiteado en `30915f4` junto con todo el trabajo de la primera etapa de esta
tanda (panel de 7 parámetros, `0044`, `0045`, "Volver" en la fila) — no había punto de corte limpio
en git entre las dos etapas (nada se había commiteado en el camino), así que quedaron en un solo
commit; el porqué completo está en el propio mensaje de ese commit. De ahí sale también la regla
nueva en `CLAUDE.md` (Reglas de edición, punto 6): cada tanda verificada se commitea antes de
arrancar la siguiente.

## 17. El "por defecto" real — `CargasSocialesDefaults`, constantes Dart — 2026-09-02

Cierra el bug anotado en §15/§16: el "por defecto X" de los 7 campos leía `config` (la
configuración ACTUAL de la obra que se está editando), no el default real de la columna. Confirmado
en uso real por el usuario: después de guardar 191 en horas mensuales, la etiqueta pasó a decir
"por defecto 191" — le devolvía como default lo que la persona acababa de escribir, y perdía la
única referencia de a qué volver.

**Fuente elegida: constantes Dart** (`lib/data/models/cargas_sociales_defaults.dart`), no una
función que lea en vivo el catálogo de Postgres (`pg_attrdef`) — esa opción se diseñó y se descartó
por desproporcionada: dos funciones nuevas en la base, una `security definer` que evalúa
expresiones del catálogo con `execute format`, un `revoke`, un modelo Dart, un método de
repositorio y una carga asíncrona más en el panel, todo para mostrar seis números en una etiqueta.
Mismo criterio que ya rige otros datos de esta pieza que cambian poco y a mano: la escala salarial
UOCRA se carga en cada paritaria sin motor automático, FICS/IERIC/FODECO viven como columna
justamente para poder corregirlas con un `UPDATE` simple.

El riesgo real de las constantes — que se desincronicen del default de la columna el día que una
migración lo cambie — se maneja por escrito, no por mecanismo: la propia clase lo dice en su
comentario ("esto NO se actualiza solo"), y `0046` (la primera migración que lo necesitó) dejó el
mismo aviso en su propio comentario, para que quien escriba la próxima migración sobre esta tabla
lo vea ahí mismo, no solo acá.

Valores actuales — reflejan el estado de la base **después** de `0046`, no los defaults originales
de `0036`/`0037`/`0038`:

| campo | columna | default | migración que lo fijó |
|---|---|---|---|
| ART | `art_pct` | 10,23 | `0036` |
| Fondo de Cese | `fondo_cese_pct` | 12 | `0036` |
| SUSS | `suss_pct` | 18 (con MiPyME) | `0036` |
| Horas mensuales | `horas_mensuales` | 190,67 | `0036`, cambiado por `0046` |
| Horas improductivas | `horas_improductivas_mensuales` | 15,62 | `0036`, cambiado por `0046` |
| Vacaciones | `vacaciones_jornales_mes` | 1 | `0037` |
| Zona UOCRA | `zona_uocra` | B | `0038` |

Entra en el mismo cambio el arreglo de `_nombreZonaInicial` (renombrado `_nombreZonaPorDefecto`),
que tenía el mismo bug: resolvía `_zonaInicial` (la zona actual de la obra), no el default. Se
sacaron del archivo `_esMiPymeInicial` y `_zonaInicial` — quedaron sin ningún uso una vez que el
"por defecto" dejó de leer la config, la única razón por la que existían.

Verificado: `flutter analyze` sin issues nuevos (28, mismo conteo que antes del cambio), `flutter
test` 36/36.

## 17. Catálogo completo de zonas UOCRA + aviso de zona sin verificar (`0048`) — 2026-09-04

Primera mitad del "PENDIENTE CRÍTICO" de §15: carga el catálogo descriptivo de las 4 zonas del CCT
76/75 (antes solo estaba Zona B) y resuelve el problema real que ese pendiente señalaba — no que el
selector pudiera fallar (ya no podía, ver más abajo), sino que un usuario fuera de Zona B no tenía
ninguna forma de enterarse de que su costo estaba mal calculado. La segunda mitad — básicos reales
de Zona A/C/C Austral, y con ellos el selector real, el gate del alta de obra y la marca de La
Pampa — queda para cuando existan esos números (ver "Lo que queda documentado sin código" al final
de esta sección).

### El aviso, no el selector, era el problema

El diagnóstico previo (§15, "PENDIENTE CRÍTICO") ya daba por buena la protección del selector:
`EscalaSalarialUocraRepository.getZonasDisponibles()` nunca ofrece una zona sin escala, así que
cargar las 4 zonas en `zonas_uocra` no habilita elegir una que rompería
`calcular_valor_hora_mano_obra`. Eso sigue intacto y sin tocar en esta tanda.

El problema real es el inverso: con una sola zona cargada, el selector se reduce a un texto fijo
("Zona B — Neuquén, Río Negro y Chubut") que no le dice a nadie que existen otras tres zonas en el
convenio. Un usuario de Córdoba lee ese texto sin ningún indicio de que no le corresponde — el
selector es seguro, pero no es informativo.

### Distinguir "cuántas zonas tienen escala" de "cuántas hay en el catálogo"

El aviso no puede usar `getZonasDisponibles()` (esa lista es, a propósito, siempre la misma que ve
el selector). Hace falta una segunda pregunta, nueva: cuántas zonas hay en total en `zonas_uocra`,
sin filtrar por escala. Se agregó `EscalaSalarialUocraRepository.getCantidadZonasEnCatalogo()`
—devuelve solo un `int`, a propósito, no una lista de `ZonaUocra`: así ese método es inutilizable
como fuente de opciones de un selector aunque alguien lo intente en el futuro, sin depender de que
respete un comentario. `CartelCostoManoObra` compara ese conteo contra `getZonasDisponibles().length`
(`_hayZonasSinCargar`) — la condición es verificable desde que se aplique `0048`: pasa a ser
`4 > 1`, sin necesitar ninguna escala nueva cargada.

### Dónde vive: el cartel, no el panel

`CartelCostoManoObra` (arriba de la sección "Mano de obra" en Mat y MO) ganó dos líneas nuevas,
siempre en el mismo lugar donde ya se explica cómo se calcula el costo:

1. **Zona vigente, siempre visible, para todos** (`Calculada con Zona B — Neuquén, Río Negro y
   Chubut`) — no depende de que haya más de una zona ni de ningún aviso. Antes de esta tanda el
   cartel no mencionaba la zona en absoluto; un usuario de Zona B tampoco tenía forma de confirmar
   con qué escala se estaba calculando su obra.
2. **Aviso descartable**, solo cuando `_hayZonasSinCargar`, con el mismo mecanismo que el aviso de
   orden de `rubros_tab.dart` (`SharedPreferences`, clave por obra
   `zona_uocra_aviso_descartado_<obraId>`, default visible, ícono chico para restaurarlo si se
   descartó). Texto final, dos correcciones sobre el primer borrador:
   - Sin fecha: no dice "en cuanto estén cargadas" — no hay ninguna fecha comprometida.
   - Con salida real: menciona el mecanismo que ya existe (fijar el valor hora a mano, por
     categoría, desde el lápiz de cada fila) en vez de solo informar el problema y dejar al usuario
     sin caminos.

   > Es la única escala del convenio UOCRA (CCT 76/75) que tenemos cargada por ahora. Si tu obra no
   > es en esas provincias, este costo no le corresponde: podés fijar el valor hora a mano en cada
   > categoría hasta que esté disponible tu zona.

No se evaluó ponerlo en `PanelParametrosCargasSociales` — ese panel solo lo abre quien ya fue a
buscar el lapicito de una categoría, y el problema que este aviso resuelve es que alguien que
**nunca** toca esa pantalla siga presupuestando con una zona equivocada sin enterarse.

### Zona UOCRA sale del gate de PRO — no es un ajuste fino como los otros seis

Hasta esta tanda, cambiar la zona pasaba por el mismo botón "Guardar" que ART/Fondo de Cese/horas/
vacaciones, gateado por PRO (`_onGuardar` en `PanelParametrosCargasSociales`). Con una sola zona
cargada eso no importaba —no había nada para elegir—, pero con el catálogo completo dejarlo así
bloqueaba a cualquier usuario Free fuera de Zona B: podía *ver* que su obra estaba mal (el aviso
nuevo se lo dice), pero no podía *corregirlo* sin pagar. Zona UOCRA no es un ajuste fino de
liquidación como ART o Fondo de Cese — es un dato de corrección básica, de la misma naturaleza que
`ubicacion` (¿dónde está la obra?), no de la naturaleza de una alícuota que un contador ajusta.

**Se sacó del formulario gateado y se hizo instantánea**, mismo patrón que el tilde
`aplica_cargas_sociales` del cartel (`_onCambiarCargasSociales`): se guarda sola apenas se elige en
el dropdown, vía `ObraPresupuestoConfigRepository.actualizarZonaUocra` (columna nueva, separada de
`actualizarCargasSociales`, que ahora manda 6 campos en vez de 7), sin ningún chequeo de PRO. RLS
no cambia — seguía y sigue exigiendo `admin_maestro`/`profesional` a nivel de base, el gate que se
sacó era enteramente de capa de app.

**Consecuencia que hubo que resolver, no solo el guardado**: como la zona ahora se guarda por fuera
del botón "Guardar" de los otros 6, "Cancelar" ya no es siempre "no se guardó nada" — si el usuario
cambió la zona y después tocó Cancelar (sin tocar el Guardar de los otros 6), la zona igual quedó
persistida en la base. `PanelParametrosCargasSociales` suma `_zonaCambioGuardado` (bandera separada
de `_guardando`/`_verificandoPro`, que son del botón Guardar) y Cancelar ahora devuelve `true` en
vez de `null` cuando esa bandera está prendida — mismo mecanismo de propagación que ya usaba
`_huboGuardadoDeParametros` en `PanelValorHoraManoObra` (§16) para que `MatYMoTab` sepa que tiene
que recargar el consolidado. Sin este ajuste, cambiar la zona y cerrar con Cancelar habría dejado
la base correcta pero las filas de Mat y MO mostrando valores viejos hasta salir y volver a la
solapa.

**Límite aceptado, no cerrado**: si el usuario cierra el diálogo tocando afuera (barrier dismiss)
en vez de un botón, la zona igual quedó guardada pero la señal de recarga no se propaga —
`MatYMoTab` queda con las filas viejas hasta el próximo refresh (pull-to-refresh, o salir y volver
a la solapa). Es el mismo comportamiento que ya tenía la cadena de diálogos para los otros 6
parámetros con barrier dismiss (no es una regresión de esta tanda), y forzar `barrierDismissible:
false` en dos diálogos anidados para cerrar ese caso puntual se evaluó y se descartó por
desproporcionado frente a lo angosto del caso.

### La Pampa — dos motivos, no uno, documentados donde corresponde

`0048` inserta Zona A con La Pampa incluida en su lista de provincias, sin ninguna marca especial
en el dato — la advertencia es capa de presentación, no columna (`zonas_uocra.descripcion` se
reusa tal cual en la etiqueta compacta del dropdown, y una advertencia larga ahí se repetiría fuera
de contexto en cada ítem). Los dos motivos por los que entra en Zona A, documentados en el
comentario de la migración porque pesan igual, no uno como desempate del otro:

1. Es la ubicación que más fuentes consultadas coinciden en darle.
2. Zona A es la escala más barata de las cuatro — si el usuario no corrige esto a mano, el error
   queda del lado que no infla el presupuesto (con Zona B pasaría lo contrario).

Sigue sin verificarse contra el texto del convenio (ver §15, "PENDIENTE CRÍTICO", punto 2).

### Lo que queda documentado sin código — mismo criterio que el gate del alta, y por el mismo motivo

Dos piezas de esta tanda se discutieron y se descartaron para escribir ahora, no por alcance sino
porque **hoy son imposibles de verificar en el emulador**: con una sola zona con escala cargada,
`getZonasDisponibles().length > 1` da `false` siempre, así que cualquier rama de código que dependa
de "hay 2 o más zonas para elegir" nunca se ejecuta hasta que se cargue una segunda escala. Ya
mordimos una vez por commitear código sin verificar (`CLAUDE.md`, Reglas de edición, punto 6) — no
repetirlo.

1. **Gate de zona en el alta de obra.** Cuando `getZonasDisponibles().length > 1`, el wizard de
   alta (Paso A, junto a `ubicacion`) tiene que pedir la zona sin ningún default preseleccionado —
   hoy preguntarla sería ruido, porque la única respuesta posible es Zona B. Mientras haya una sola
   zona con escala, la fila de `obra_presupuesto_config` se sigue sembrando sola por trigger, sin
   cambios.
2. **Marca de "a verificar" en el ítem de Zona A del selector.** Aplica al mismo `_buildCampoZona`
   de `PanelParametrosCargasSociales` — hoy solo puede mostrar Zona B (texto fijo), así que el
   branch de 2+ zonas donde viviría esta marca tampoco se ejecuta nunca en el emulador. Texto ya
   redactado, listo para pegar cuando se cargue la escala de Zona A:
   - Marca inline junto a "La Pampa" en la lista de provincias de la zona: `La Pampa*` (o el ícono
     ⚠ chico, a definir en el momento contra el estilo real del dropdown).
   - Nota al pie, solo cuando el ítem de Zona A está seleccionado/visible: *"El convenio no es
     unánime sobre La Pampa: las fuentes consultadas no coinciden. La ubicamos en Zona A porque es
     lo que indica la mayoría. Si tu obra es en La Pampa, confirmalo con tu contador o con la
     seccional de UOCRA."*

**Además, retroactivo, sin código posible hoy porque depende de que exista una obra real en Zona A
para revisar:** el día que se cargue la escala de Zona A, todas las obras creadas antes de ese día
quedan en `zona_uocra = 'B'` sin que nadie la haya elegido — el gate del punto 1 protege obras
nuevas, no las existentes. Ese día hay que revisar a mano las obras con `zona_uocra = 'B'` y
confirmar con cada usuario si corresponde.

### Archivos tocados

- `supabase/migrations/0048_zonas_uocra_catalogo_completo.sql` — 3 `insert` en `zonas_uocra` +
  FK `obra_presupuesto_config.zona_uocra → zonas_uocra(codigo)`. Sin aplicar todavía, sin acceso a
  la base desde este entorno — lo corre el usuario a mano.
- `lib/services/escala_salarial_uocra_repository.dart` — `getCantidadZonasEnCatalogo()`.
- `lib/services/obra_presupuesto_config_repository.dart` — `actualizarZonaUocra()` nuevo,
  `actualizarCargasSociales()` pierde el parámetro `zonaUocra` (6 campos, no 7).
- `lib/presentation/obra_detalle/tabs/panel_parametros_cargas_sociales.dart` — `_onCambiarZona`
  instantáneo sin gate de PRO, `_zonaCambioGuardado` propagado por Cancelar.
- `lib/presentation/obra_detalle/tabs/cartel_costo_mano_obra.dart` — zona vigente siempre visible,
  aviso descartable de "hay otras zonas sin cargar".

### Sin verificar en el emulador todavía

Pendiente de que el usuario aplique `0048` en Supabase y corra la app: confirmar que el cartel
muestra "Calculada con Zona B — Neuquén, Río Negro y Chubut" seguido del aviso nuevo (sin
descartar), que descartarlo y reabrir la obra lo deja descartado, que el ícono lo restaura, y que
cambiar de plan (si hubiera más de una zona) ya no queda bloqueado — este último caso en particular
no se puede probar hasta que exista una segunda zona con escala, ver arriba.
