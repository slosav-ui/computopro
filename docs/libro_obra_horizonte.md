# Libro de Obra — horizonte (anotado, sin diseñar)

**Solo para no perderlo — salió de una conversación del 2026-09-11, todavía no está en ningún
otro lado del proyecto. No es un diseño cerrado, no hay ninguna migración ni pantalla planeada
todavía.** Cuando se decida encarar esta pieza, retomar desde acá.

## La visión completa, en palabras de Seba

**"Todo llevar la obra acá"** — el respaldo documental completo de la obra, en un solo lugar
asociado a esa obra. Hoy vive repartido entre un cuaderno físico, WhatsApp y una carpeta de
papeles. Criterio rector: **"siempre simplificar para los profesionales y los constructores, que
no sea tedioso"** — nadie en obra, con el casco puesto, va a tipear un texto largo parado.

Son cuatro piezas, no una:

1. **El Libro de Obra** — notas escritas **y audios**. Poder dictar es clave, no un agregado
   menor: es la forma en la que alguien en obra realmente va a usarlo.
2. **Órdenes de Servicio** — lo que el Profesional le indica al Constructor.
3. **Notas de Pedido** — al revés, lo que el Constructor le pide al Profesional.
4. **Archivo de documentación de la obra** — remitos, facturas, presupuestos de terceros. **No es
   el importador de PDF del roadmap** (ese sube planos para pedir un Servicio Especial, pieza
   totalmente distinta que ya está anotada aparte en `docs/diagnostico_general_producto.md` §5) —
   acá es documentación administrativa de la obra en curso, sin relación con pedir un servicio.

Ningún competidor tiene esto en un solo lugar asociado a la obra — es una ventaja real, no una
pieza cosmética.

## Qué ya existe (auditado contra el código, ver `docs/gestion_obra_estado_real_auditoria.md` §5-bis)

- Tabla `libro_entradas` aplicada, con su discriminador (`obra`/`orden_servicio`/`nota_pedido`).
- La matriz de quién genera y quién responde, por libro, aplicada en RLS.
- Append-only (sin `UPDATE`/`DELETE`) — coherente con ser un respaldo, no un documento editable.
- Modelo Dart (`libro_entrada.dart`) ya existe.

**Falta el repositorio y la pantalla — ninguna de las 4 piezas tiene un solo punto de entrada
desde la app hoy.**

## Tres decisiones pendientes, para cuando se retome — necesitan a Seba, no se resuelven solas

**1 · Numeración y secuencia.** En obra real, las Órdenes de Servicio van numeradas y
correlativas, y normalmente la anterior se responde (acuse de recibo) antes de poder emitir la
siguiente — la misma lógica de secuencia que ya tiene `certificados.numero`. Hoy `libro_entradas`
no tiene ningún concepto de esto. Falta decidir si se quiere esa formalidad o si el diseño actual
(sin número, sin candado de secuencia) alcanza.

**2 · El aviso legal.** El libro rubricado en papel es el que tiene validez legal ante el colegio
profesional o el municipio — esto es un respaldo interno, y conviene que la app lo diga
explícitamente para no generar una falsa sensación de validez legal equivalente. La intención ya
estaba anotada en el diseño de Etapa 3 (citada ahí como "§F", una sección que en los hechos nunca
se escribió en ningún documento) pero el texto exacto del aviso nunca se redactó.

**3 · Los audios — cero definición en todo el proyecto hasta esta conversación.**

Lectura de Claude Code, para cuando se decida, no una definición cerrada: **guardar el audio
siempre, y transcribirlo si se puede** — el audio es la prueba (lo que realmente se dijo, con
fecha y quién lo dijo), el texto transcripto sirve para buscar y leer rápido sin tener que
escuchar cada nota. Transcribir necesita un servicio externo con costo por minuto/uso — se puede
arrancar guardando solo el audio (ya funciona la infraestructura real de subida de archivos,
Supabase Storage, probada en el importador de Excel/PDF) y sumar la transcripción como mejora
posterior, sin que eso bloquee la primera versión.

## Fuera de esto, sin tocar

El importador de PDF/foto con IA del roadmap (`docs/diagnostico_general_producto.md` §5) es una
pieza completamente aparte — comparten la palabra "documentación" pero no el propósito. No
confundirlos al retomar ninguno de los dos.
