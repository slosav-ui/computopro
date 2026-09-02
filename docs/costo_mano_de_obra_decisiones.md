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

- **`suss_pct` no puede ser un número libre en la UI.** Un campo que dice "SUSS" no le dice nada a
  nadie. Tiene que ser una elección con nombre: *"Con certificado MiPyME — 18%"* / *"Sin certificado
  MiPyME — 20,4%"* — convierte una pregunta técnica en una que el usuario sabe contestar.
- **El cartel en modo "sin cargas" no puede mostrar el `multiplicador` que devuelve la función en
  ese modo** (cae a ~1,13, matemáticamente correcto pero no es lo que el usuario necesita ver ahí).
  Tiene que seguir mostrando el multiplicador **con cargas** (≈1,72×), con un texto tipo "con
  cargas sería 1,72×" — lo que el usuario quiere saber al destildar es cuánto se está ahorrando,
  no el ratio recalculado sobre la base más chica.
- Bloque plegable como primer elemento de la solapa APU (mismo patrón que el Factor K, ver
  `CLAUDE.md` § "Bloque Factor K en Solapa APU"), con el desglose línea por línea de este documento
  disponible para quien quiera verlo, no solo el número final.
