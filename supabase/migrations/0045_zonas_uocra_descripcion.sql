-- Costo de mano de obra — Paso 5, tanda 2 (corrección post-verificación): "Zona B" sola en
-- pantalla no le dice a nadie qué provincias abarca. Ver docs/costo_mano_de_obra_decisiones.md §15
-- para el detalle completo de la decisión (tabla catálogo vs. columna repetida en cada fila de
-- escala_salarial_uocra, y por qué se eligió la tabla).
--
-- Tabla catálogo, no columna en escala_salarial_uocra: la descripción es un dato por zona, no por
-- fila de escala — y escala_salarial_uocra va a acumular una fila nueva por categoría en cada
-- paritaria (5 categorías × N vigencias por zona, ver 0036 y el diseño de vigencia_desde). Una
-- columna de descripción ahí la repetiría 5 veces por paritaria, cada vez; una tabla aparte la
-- guarda una sola vez por zona, se actualiza en un solo lugar.
--
-- FK desde escala_salarial_uocra.zona hacia zonas_uocra.codigo: agregado como beneficio de
-- integridad aparte (evita un typo de zona en una futura carga de escala que hoy pasaría
-- silencioso), no porque resuelva por sí sola la disciplina de "no cargar una zona sin escala" —
-- esa sigue siendo una decisión manual del usuario al cargar cada paritaria nueva, la FK solo
-- evita la mitad del error (escala sin catálogo), no la otra (catálogo sin escala, que tampoco se
-- fuerza a propósito: no hay problema en tener la descripción de una zona sin escala cargada
-- todavía, distinto es el `RAISE EXCEPTION` de calcular_valor_hora_mano_obra si una OBRA apunta a
-- esa zona sin escala — ese caso lo sigue cubriendo el selector de UI, ver §12).
--
-- Solo se siembra Zona B — es la única con escala cargada hoy. Las otras 3 zonas reales del
-- CCT 76/75 quedan documentadas acá como referencia para cuando se cargue su escala, no como dato
-- vivo:
--
--   Zona A: CABA y las provincias de Buenos Aires, Santiago del Estero, Santa Fe, Mendoza, San
--     Juan, Catamarca, Córdoba, Entre Ríos, Salta, Tucumán, Chaco, San Luis, Corrientes, La Rioja,
--     Formosa, Jujuy y Misiones.
--   Zona C: Santa Cruz.
--   Zona C Austral: Tierra del Fuego.
--
--   PENDIENTE, sin resolver: La Pampa aparece en Zona A según algunas fuentes y en Zona B según
--   otras — no verificado contra el texto del CCT 76/75 en sí, solo contra notas de terceros. No
--   bloquea hoy (Zona B es la única cargada, y La Pampa no está en discusión ahí), pero HAY QUE
--   verificarlo contra el convenio real antes de cargar la escala de Zona A y decidir en qué
--   descripción entra.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table zonas_uocra (
  codigo text primary key,
  nombre text not null,
  descripcion text not null
);

alter table zonas_uocra enable row level security;

-- Mismo patrón que escala_salarial_uocra/insumos/rubros (catálogo oficial): lectura abierta a
-- cualquier autenticado, sin política de escritura — se carga a mano vía SQL Editor junto con cada
-- escala nueva.
create policy zonas_uocra_select on zonas_uocra for select
using (auth.uid() is not null);

insert into zonas_uocra (codigo, nombre, descripcion) values
  ('B', 'Zona B', 'Neuquén, Río Negro y Chubut');

-- La FK exige que la fila de zonas_uocra exista antes que cualquier fila de escala_salarial_uocra
-- que la referencie — ya se cumple para Zona B, sembrada arriba en esta misma migración.
alter table escala_salarial_uocra
  add constraint escala_salarial_uocra_zona_fkey foreign key (zona) references zonas_uocra(codigo);
