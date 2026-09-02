# Costo de mano de obra: decisiones cerradas

Documento de referencia único para la pieza de costo de mano de obra (valor hora por categoría
UOCRA + cargas sociales, Solapa 3). Nace porque el fundamento de esta pieza venía quedando repartido
entre comentarios sueltos de migraciones y conversaciones que no dejan rastro escrito — leer este
archivo antes de retomar el tema, en vez de rediscutir algo que ya está resuelto.

Resumen ejecutivo en `CLAUDE.md`, sección "Costo de mano de obra: escala UOCRA y cargas sociales".
Schema real: `supabase/migrations/0036` a `0040`. Función: `calcular_valor_hora_mano_obra(obra_id,
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
