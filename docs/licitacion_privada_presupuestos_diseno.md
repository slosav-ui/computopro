# Licitación privada de presupuestos — diseño de negocio (2026-09-10)

**Estado: diseño cerrado en su lógica de negocio, sin implementar.** Ningún archivo de `lib/` ni
tabla de Supabase fue tocado para este documento — es la conversación de diseño, consolidada antes
de construir nada. No incluye diseño de datos (tablas, RLS, modelos Dart) todavía; eso es el paso
siguiente, cuando se decida empezar esta pieza.

Es una pieza nueva y más grande que las invitaciones — depende de que las invitaciones existan
primero (ver "Relación con lo que ya existe" al final).

---

## 1. El caso real que resuelve

Un cliente contrata a un profesional. El profesional carga la obra, hace el cómputo y le pasa un
número aproximado. Después buscan constructor, y **le piden presupuesto a tres.**

Hoy eso se hace con Excel, WhatsApp y una planilla al costado para comparar. El trabajo tedioso no
es cargar los tres presupuestos: **es descubrir que no son comparables.** Uno cotiza la
mampostería con material y otro solo la mano de obra. Uno incluye el revoque en la partida y el
otro lo pone aparte. Uno se olvidó dos rubros. Eso hoy se descubre a mano, renglón por renglón.

## 2. La idea central

**El profesional arma la planilla a presupuestar y se la manda a los constructores.** Todos
cotizan sobre la misma estructura, así que la comparación deja de ser peras con manzanas por
definición.

Dos variantes, las dos reales:

- **Con el cómputo hecho**: el profesional midió y el constructor solo pone precios. Comparar es
  directo.
- **Sin el cómputo**: cada constructor mide y cotiza. Ahí las cantidades pueden diferir, **y esa
  diferencia es información valiosa** — si uno midió 200 m² y otro 150, alguien se equivocó. La
  comparación tiene que mostrar cómputo y precio, no solo el total.

## 3. Cómo llega la planilla al constructor

**Por invitación desde la app, por Excel o por PDF. Siempre generada desde la app.**

Clave: **el constructor no necesita ser usuario.** Recibe la planilla, la llena como siempre, la
manda de vuelta, y el profesional la carga. Es lo mismo que ya hace hoy, pero con el formato que el
profesional controla en vez de que cada constructor improvise el suyo.

## 4. Qué tiene que resolver la comparación

No alcanza con mostrar tres columnas de números. Lo que un profesional necesita ver de un vistazo:

- **Qué partidas cotizó cada uno y cuáles faltan.** Si uno no cotizó instalaciones, comparar los
  totales no significa nada.
- **Dónde hay diferencias grandes.** Si en mampostería uno está 40% abajo, o se equivocó o entendió
  otra cosa distinta — eso es lo que hay que mirar primero.
- **Si están cotizando lo mismo.** Con material o sin material, que es la confusión más común.
- **Las cantidades**, cuando cada uno hizo su propio cómputo (variante "sin cómputo" del punto 2).

## 5. Las preguntas automáticas — el diferencial real

Además de comparar, **la app genera las preguntas que hay que hacerle a cada constructor.** Sale
de tres fuentes:

1. **De lo que falta.** *"No cotizaste limpieza de obra, ¿lo incluís o va aparte?"*
2. **De lo que está fuera de rango.** *"Tu precio de mampostería está 40% abajo de los otros dos,
   ¿cotizaste con material?"*
3. **De lo que siempre se olvida** — una lista fija que sale de la experiencia de obra: fletes,
   gestión de materiales, andamios, limpieza final, ayuda de gremios.

El punto 3 es el más valioso, porque es criterio profesional que la app aporta, no un cálculo —
mismo tipo de activo que el split del Factor K (`docs/factor_k_apu_decisiones.md`).

**Abierto: la lista del punto 3 todavía no está armada — la tiene que escribir Seba.** Es lo único
que queda abierto de esta pieza aparte de lo del §9.

## 6. Elección y aprobación

**El profesional elige uno y lo marca como recomendado.** Recomienda, no decide: la obra la paga el
cliente.

Dos caminos, según cómo trabajen profesional y cliente:

- **A distancia**: el profesional le manda los tres al cliente con uno recomendado. El cliente los
  ve, pregunta lo que quiera, y aprueba desde la app.
- **Presencial**: están sentados mirando los tres juntos y deciden ahí mismo. El profesional marca
  el aprobado sin ida y vuelta.

Por qué hace falta el segundo camino, textual de Seba: *"sería tedioso hablarlo, te mando, lo
aprobás y después bla bla bla"*. Si ya decidieron juntos, una aprobación formal por la app sobra.

**Reglas cerradas sobre la aprobación:**

- En los dos casos queda registrado quién aprobó y cuándo.
- En el camino presencial, **tiene que quedar explícito que se aprobó así** — no para desconfiar,
  sino porque es distinto de que el cliente lo haya aprobado él mismo, y el cliente tiene que poder
  ver esa distinción después.
- **El cliente ve los tres, no solo el recomendado** — aunque sea para confirmar que el profesional
  eligió bien.

## 7. Qué pasa con los que no se eligieron

**Se conservan, no se descartan.** Dos motivos:

- **Son el respaldo de la decisión.** Si en seis meses el cliente pregunta por qué se eligió a ese
  constructor, el profesional muestra que había tres y por qué.
- **Si el elegido se cae**, está el segundo a mano sin volver a pedir cotizaciones.

El aprobado pasa a ser el presupuesto de la obra: lo que después se certifica (ver
`docs/certificados_ciclo_vida_diseno_datos.md`).

## 8. Permisos y planes — resuelto

Al invitar, el administrador otorga rol y permisos (mecanismo de `obra_members`, Etapa 3 —
`docs/etapa3_roles_permisos_diseno_datos.md`). **Pero un permiso no puede regalar PRO.**

**El riesgo**: si el administrador puede dar "ver APU completo" a quien quiera, un profesional
invita a tres colegas y les da el diferencial pago sin que ninguno pague.

**Solución cerrada: el permiso se otorga igual, pero el plan del invitado decide si lo puede
usar.** Si le das "ver APU" y él es Free, no lo ve, y al invitarlo un cartel avisa que ese permiso
requiere PRO.

El administrador no queda bloqueado al otorgar el permiso, y el invitado ve que hay algo que no
puede ver — que funciona como incentivo de conversión, no como fricción.

## 9. Estrategia de adopción

Esto saca al constructor de su zona de confort, así que la barrera hay que bajarla en cada paso.

1. **Primero: que la planilla llegue en el formato que ya usa.** Si recibe un Excel que abre y
   llena como siempre, no cambió nada para él — la app está del lado del profesional, no del suyo.
   Resistencia cero.
2. **Después: que la planilla sea mejor que la que él hace.** Con rubros ordenados, unidades
   puestas y el cómputo ya medido, le ahorra lo más tedioso. La primera vez la llena porque se la
   pidieron; la segunda la prefiere.
3. **El paso a la app lo da él cuando le conviene**, no cuando el profesional se lo pide. El
   momento natural es la segunda o tercera planilla: ahí registrarse le ahorra volver a cargar sus
   precios, porque su catálogo queda guardado.
4. **Nunca bloquear el camino viejo.** Si en algún momento la única forma de cotizar es dentro de
   la app, el que no quiso migrar se va y se lleva al profesional con él. El Excel tiene que seguir
   funcionando siempre.

Dos reglas más de adopción, cerradas:

- **El que empuja la adopción es el profesional, no el marketing.** Si manda la planilla a diez
  constructores, esos diez la vieron. El esfuerzo comercial se concentra en un solo tipo de
  usuario — el profesional — no en llegar a cada constructor por separado.
- **El primer uso tiene que dar un resultado visible.** Si el profesional carga tres presupuestos y
  la app le muestra que uno se olvidó dos rubros, eso lo cuenta a sus colegas. Es la publicidad que
  no se compra.

## 10. Lo que queda abierto

- **La lista de preguntas frecuentes** (§5, punto 3) — qué se olvidan de cotizar los constructores
  en la práctica. La tiene que armar Seba, no se puede inferir del código ni de la spec.
- **Presupuestar desde cuentas propias de cada constructor** (en vez de que el profesional cargue
  los tres a mano): necesita una capa de precios por usuario sobre el mismo cómputo. La base
  conceptual ya existe — las APU son privadas de su creador (`docs/etapa3_roles_permisos_diseno_datos.md`
  §3) y los precios manuales ya son por obra (Mat y MO, consolidado + edición manual con marca de
  origen) — pero el mecanismo de "tres cotizaciones en paralelo sobre la misma obra, cada una con
  su propio precio" no está diseñado. **Queda para cuando haya constructores usando la app de
  verdad**, no antes.

## 11. Relación con lo que ya existe

Esta pieza se apoya en piezas ya cerradas:

- El importador de Excel funcionando (`docs/importador_capa1_diseno_datos.md`,
  `docs/importador_capa2_diseno_datos.md`).
- Las APU privadas por creador y los precios manuales por obra (Etapa 3, Mat y MO).
- `obra_members` con roles combinables, RLS aplicado (`docs/etapa3_roles_permisos_diseno_datos.md`).

Y necesita dos piezas que hoy no existen:

- **Las invitaciones** — mecanismo en cero, sin una sola línea de código (ver
  `docs/diagnostico_general_producto.md` §6 punto 4). Esta pieza depende de que las invitaciones
  existan primero: "por invitación desde la app" (§3) no se puede construir sin ellas.
- **El importador de PDF y foto** — en backlog (`docs/diagnostico_general_producto.md` §5), lo
  necesita la variante en que el constructor manda su cotización como PDF/foto en vez de Excel.
