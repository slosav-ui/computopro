-- Rubros/APU parte 2 — Migración 3: tabla `subitems`, sembrada con el catálogo real de
-- PLANILLA_BASE_2_0_v3_CORREGIDA.ods (hoja RUBROS), excluyendo las filas "OTRO" de cada rubro
-- (esas se resuelven vía obra_subitems.descripcion_libre más adelante, no son catálogo).
-- Ver docs/rubros_apu_diseno_datos.md §2.2 para el diseño completo.
--
-- Deliberadamente sin precio propio (ni sugerido ni unitario) — el precio de un subítem sale de
-- su apu_composicion aplicada sobre insumos vigentes, o del precio manual en obra_subitems para
-- los rubros con usa_apu = false. Guardar un precio acá sería una segunda fuente de verdad.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

create table subitems (
  id uuid primary key default gen_random_uuid(),
  rubro_id uuid not null references rubros(id) on delete cascade,
  codigo text not null,                     -- "1.1", "12.10", etc. (jerárquico, no numérico puro)
  descripcion text not null,
  unidad text not null,
  creador_usuario_id uuid references auth.users(id),  -- null = catálogo oficial
  created_at timestamptz not null default now()
);

create unique index subitems_codigo_oficial_unique on subitems (codigo)
  where creador_usuario_id is null;

-- =====================================================================
-- Seed: 116 subitems reales (excluye filas OTRO y SUBTOTAL de cada rubro)
-- =====================================================================
--
-- (rubro_codigo, codigo, descripcion, unidad) — el join contra rubros por codigo solo resuelve
-- filas oficiales (creador_usuario_id is null), coherente con el índice único de arriba y con el
-- de rubros (0015_rubros.sql).

insert into subitems (rubro_id, codigo, descripcion, unidad)
select r.id, v.codigo, v.descripcion, v.unidad
from (values
  ('1', '1.1', 'Replanteo y nivelacion', 'M2 O GL.'),
  ('1', '1.2', 'construcciones provisorias (obrador, baño quimico, deposito)', 'M2 O GL.'),
  ('1', '1.3', 'cerco de obra', 'Ml'),
  ('1', '1.4', 'retiro de escombros', 'm3'),
  ('1', '1.5', 'Instalacion provisoria (agua, luz, fuerza motriz)', 'Gl.'),
  ('1', '1.6', 'corte de arboles y extraccion de raices', 'UND.'),
  ('1', '1.7', 'Desmonte y perfilado de terreno', 'm3'),
  ('1', '1.8', 'Demolicion de mamposterias / estructuras', 'M3 O M2'),
  ('1', '1.9', 'Limpieza y desmalezamientos de terrenos', 'M2 O GL.'),
  ('1', '1.10', 'cartel de obra.', 'UND O M2'),
  ('2', '2.1', 'EXCACACION DE ZANJAS ( profundidad maxima 1,5m)', 'M3'),
  ('2', '2.2', 'EXCACACION DE POZOS (para pozos negros, pozos romanos, etc., y profundidades no mayores a 8m)', 'M3'),
  ('2', '2.3', 'EXCACACION DE POZOS (para bases de columnas, tanques enterrados, y profundidades no mayores a 4m)', 'M3'),
  ('3', '3.1', 'BASES', 'M3'),
  ('3', '3.2', 'TRONCO DE COLUMNAS', 'M3'),
  ('3', '3.3', 'VIGAS DE FUNDACIONES', 'M3'),
  ('3', '3.4', 'PLATEAS DE FUNDACIONES', 'M3'),
  ('4', '4.1', 'COLUMNAS', 'M3'),
  ('4', '4.2', 'LOSAS', 'M3'),
  ('4', '4.3', 'VIGAS', 'M3'),
  ('4', '4.4', 'TABIQUES', 'M3'),
  ('4', '4.5', 'ESCALERAS', 'M3'),
  ('4', '4.6', 'ENCADENADOS', 'M3'),
  ('4', '4.7', 'TANQUE RECTANGULAR', 'M3'),
  ('5', '5.1', 'CERRAMIENTOS EXTERIORES PB (Perfil CSH PGC 100x40x0,9, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclaje Escuadra HTT14, Broca Mecanica 10)', 'M2'),
  ('5', '5.2', 'CERRAMIENTOS EXTERIORES 1° Y 2° PISO (Perfil CSH PGC 100x40x0,9, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclaje Escuadra HTT14, Broca Mecanica 10)', 'M2'),
  ('5', '5.3', 'CERRAMIENTOS INTERIORES PB - 1° Y 2° PISO (Perfil CSH PGC 100x40x0,9, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclaje Escuadra HTT14, Broca Mecanica 10)', 'M2'),
  ('5', '5.4', 'ENTREPISOS (Placa fenolica de 18mm, Perfil CSH PGC 150x40x0,9, Aislacion acustica 100mm)', 'M2'),
  ('5', '5.5', 'ESCALERAS (Perfil CSH PGC 100x40x0,9, Placa OSB de 11.1mm)', 'M2'),
  ('5', '5.6', 'CUBIERTAS INCLINADAS (Perfil CSH PGC 100x40x0,9, Placa OSB de 11.1mm, aislacion hidraulica, realces, alfajias 2”x2”, aislacion termica, chapa sinusoidal)', 'M2'),
  ('6', '6.1', 'CERRAMIENTOS EXTERIORES PB (Ecuadras de madera 4”x2”, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclajes Metalicos, Broca Mecanica 10)', 'M2'),
  ('6', '6.2', 'CERRAMIENTOS EXTERIORES 1° Y 2° PISO (Ecuadras de madera 4”x2”, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclajes Metalicos, Broca Mecanica 10)', 'M2'),
  ('6', '6.3', 'CERRAMIENTOS INTERIORES PB - 1° Y 2° PISO (Ecuadras de madera 4”x2”, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclajes Metalicos, Broca Mecanica 10)', 'M2'),
  ('6', '6.4', 'ENTREPISOS (Placa fenolica de 18mm, Cabios de madera 6”x2”, Aislacion Termica 100mm, Placa OSB 11,1 ambas caras, Anclajes Metalicos, Broca Mecanica 10), Aislacion acustica 100mm)', 'M2'),
  ('6', '6.5', 'ESCALERAS (Escuadras de madera 6”x2”, Placa Fenolicas de 18mm)', 'M2'),
  ('6', '6.6', 'CUBIERTAS INCLINADAS (Cabios de 6”x2”, Placa OSB de 11.1mm o machimbre 4”x1/2”, aislacion hidraulica, realces, alfajias 2”x2”, aislacion termica, chapa sinusoidal)', 'M2'),
  ('7', '7.1', 'MONTAJE DE COLUMNAS Y VIGAS en perfil tubular estructural cuadrado/rectangular conformado en frio.', 'KG'),
  ('7', '7.2', 'MONTAJE DE COLUMNAS / VIGAS / CORREAS en perfil tubular rectangular o perfil C conformado en frío', 'KG'),
  ('7', '7.3', 'MONTAJE DE CERCHAS / TIJERALES LIVIANOS en caño estructural o perfil C conformado en frío', 'KG'),
  ('8', '8.1', 'LADRILLOS COMUNES e=15cm', 'M2'),
  ('8', '8.2', 'LADRILLOS COMUNES A LA VISTA e=15cm', 'M2'),
  ('8', '8.3', 'LADRILLOS COMUNES e=30cm', 'M2'),
  ('8', '8.4', 'LADRILLOS COMUNES A LA VISTA e=30cm', 'M2'),
  ('8', '8.5', 'LADRILLOS CERAMICOS PORTANTES 18/19/33', 'M2'),
  ('8', '8.6', 'LADRILLOS CERAMICOS HUECOS 8/18/33', 'M2'),
  ('8', '8.7', 'LADRILLOS CERAMICOS HUECOS 12/18/33', 'M2'),
  ('8', '8.8', 'LADRILLOS CERAMICOS HUECOS 18/18/33', 'M2'),
  ('8', '8.9', 'MUROS BLOQUES DE CEMENTO 19x19x39', 'M2'),
  ('8', '8.10', 'LADRILLOS MACIZOS HCCA (RETAK) e=10cm', 'M2'),
  ('8', '8.11', 'LADRILLOS MACIZOS HCCA (RETAK) e=15cm', 'M2'),
  ('8', '8.12', 'LADRILLOS MACIZOS HCCA (RETAK) e=20cm', 'M2'),
  ('9', '9.1', 'AISLACION HIDROFUGA HORIZONTAL e=2cm', 'M2'),
  ('9', '9.2', 'AZOTADO HIDROFUGO VERTICAL e=1cm', 'M2'),
  ('9', '9.3', 'CARPETA HIDROFUGA e=2cm', 'M2'),
  ('10', '10.1', 'REVOQUE GRUESO PARA INTERIORES', 'M2'),
  ('10', '10.2', 'REVOQUE GRUESO ESPECIAL PARA EXTERIORES', 'M2'),
  ('10', '10.3', 'REVOQUE GRUESO Y FINO A LA CAL INTERIOR COMPLETO', 'M2'),
  ('10', '10.4', 'REVOQUE GRUESO Y FINO A LA CAL EXTERIOR COMPLETO (con hidrofugo)', 'M2'),
  ('10', '10.5', 'ENLUCIDO A LA CAL (aplicado sobre revoque grueso)', 'M2'),
  ('10', '10.6', 'ENLUCIDO DE YESO (sobre revoque grueso)', 'M2'),
  ('10', '10.7', 'ENLUCIDO DE YESO REFORZADO CON CEMENTO', 'M2'),
  ('11', '11.1', 'CONTRAPISO DE HORMIGON DE CASCOTES e=10cm', 'M2'),
  ('11', '11.2', 'CONTRAPISO DE HORMIGON ARMADO (con malla electrosoldada y EPS 2cm) esp total = 8cm', 'M2'),
  ('11', '11.3', 'CONTRAPISO DE MATERIAL AISLANTE (arcilla expandida) e=6cm', 'M2'),
  ('11', '11.4', 'CONTRAPISO DE MATERIAL AISLANTE (con perlas de EPS) e=6cm', 'M2'),
  ('11', '11.5', 'CONTRAPISO EXTERIOR DE HORMIGON ARMADO (con malla electrosoldada) esp total = 8cm', 'M2'),
  ('11', '11.6', 'CARPETA CEMENTICIA e=2.5cm', 'M2'),
  ('12', '12.1', 'PISO PORCELANATO (piezas pequeñas y medianas < 60/60)', 'M2'),
  ('12', '12.2', 'PISO PORCELANATO (piezas grandes > 60/60)', 'M2'),
  ('12', '12.3', 'PISO CERAMICO', 'M2'),
  ('12', '12.4', 'PISO FLOTANTE MDF/HDF', 'M2'),
  ('12', '12.5', 'PISO FLOTANTE VINILICO', 'M2'),
  ('12', '12.6', 'PISO BALDOZAS CEMENTICIAS 40/40', 'M2'),
  ('12', '12.7', 'PISO LADRILLOS COMUNES', 'M2'),
  ('12', '12.8', 'PISO PIEDRA LAJA (sobre contrapiso o carpeta)', 'M2'),
  ('12', '12.9', 'BLOQUE DE HORMIGON CALADO 30/30 e=8cm (para cesped)', 'M2'),
  ('12', '12.10', 'ZOCALO DE MADERA (incluye pintura)', 'ML'),
  ('12', '12.11', 'ZOCALO CERAMICO O PORCELANATO h=8cm', 'ML'),
  ('12', '12.12', 'ZOCALO MDF O VINILICO', 'ML'),
  ('13', '13.1', 'REVESTIMIENTO PORCELANATO (piezas pequeñas y medianas < 60/60)', 'M2'),
  ('13', '13.2', 'REVESTIMIENTO PORCELANATO (piezas grandes > 60/60)', 'M2'),
  ('13', '13.3', 'REVESTIMIENTO CERAMICOS', 'M2'),
  ('13', '13.4', 'REVESTIMIENTO DE MICROCEMENTO', 'M2'),
  ('13', '13.5', 'REVESTIMIENTO MOLON DE PIEDRA e= de 10 a 15cm', 'M2'),
  ('13', '13.6', 'REVESTIMIENTO BASE COAT (sobre bloque macizo HCCA, malla de fibra gram: 160g/m2 y base-coat)', 'M2'),
  ('13', '13.7', 'REVESTIMIENTO PLASTICO (tipo Tarquini, Revear o similar)', 'M2'),
  ('14', '14.1', 'TIPO SISTEMA EIFS (sobre revoque grueso existente u OSB compuesta por aislacion hidrofuga tipo tybek, realces, placa de EPS alta densidad 50mm, malla de fibra gram: 160g/m2 y base-coat)', 'M2'),
  ('14', '14.2', 'REVESTIMIENTO PLACA SIDING CEMENTICIO O SUPERBOARD (Barrera hidrofuga y viento tipo tybek, omegas reforzadas o alfajias 1”x1.12”, placa siding o superboard', 'M2'),
  ('14', '14.3', 'REVESTIMIENTO CHAPA PAREDES EXTERIORES fijada sobre estructura existente (aislacion hidrofuga tipo tybek, realces, alfajias de madera cepillada 2" x 2", EPS o Lana de vidrios 50mm y chapa sinusoidal o trapezoidal)', 'M2'),
  ('14', '14.4', 'REVESTIMIENTO MADERA PAREDES EXTERIORES fijada sobre estructura existente (aislacion hidrofuga tipo tybek, realces, alfajias de madera cepillada 2" x 2", EPS o Lana de vidrios 50mm y tablas de madera 6”x1”)', 'M2'),
  ('14', '14.5', 'REVESTIMIENTO CARA INTERIOR CON PLACA DE YESO DE ROCA de 12,5mm encintada y masillada con tres manos (sobre placa OSB o estructura existente, no incluye lijado)', 'M2'),
  ('14', '14.6', 'REVESTIMIENTO INTERIOR CON MACHIMBRE DE PINO DE ½" × 4" (colocado horizontalmente sobre bastidor/listones de madera, separados cada 0,40 m, con fijación mecánica y terminación barnizada)', 'M2'),
  ('15', '15.1', 'CUBIERTAS PLANAS (no accesibles)', 'M2'),
  ('15', '15.2', 'CUBIERTAS PLANAS (accesibles)', 'M2'),
  ('15', '15.3', 'CUBIERTAS INCLINADAS DE MADERA(Cabios de 6”x2”, Placa OSB de 11.1mm o machimbre 4”x1/2”, aislacion hidraulica, realces, alfajias 2”x2”, aislacion termica, chapa sinusoidal)', 'M2'),
  ('15', '15.4', 'CUBIERTAS VERDES (Extensiva, sobre estructura existrente, e=10cm)', 'M2'),
  ('15', '15.5', 'REVESTIMIENTO CARA INTERIOR CON PLACA DE YESO DE ROCA de 12,5mm encintada y masillada con tres manos (sobre placa OSB o estructura existente, no incluye lijado)', 'M2'),
  ('16', '16.1', 'APLICADO DE YESO (Sobre losa de Hormigón Armado)', 'M2'),
  ('16', '16.2', 'SUSPENDIDO TRADICIONAL DE YESO (Cal/Yeso s/ Metal Desplegado)', 'M2'),
  ('16', '16.3', 'JUNTA TOMADA (Placa yeso de roca 12.5mm c/ estructura 0.4m (Durlock/Knauf))', 'M2'),
  ('16', '16.4', 'DESMONTABLE TÉCNICO (Placas 60cm x 60cm o 60cm x 120cm)', 'M2'),
  ('16', '16.5', 'SUSPENDIDO DE MADERA / MACHIMBRADO (Vista / Interior, incluye e manso de pintura al barniz)', 'M2'),
  ('17', '17.1', 'LÁTEX INTERIOR (Planchado general con Enduido y 3 Manos)', 'M2'),
  ('17', '17.2', 'LÁTEX EXTERIOR / IMPERMEABILIZANTE (Frente y Muros Exterior)', 'M2'),
  ('17', '17.3', 'SINTÉTICO / ESMALTE (Sobre Herrería / Estructuras Metálicas)', 'M2'),
  ('17', '17.4', 'BARNIZ / IMPREGNANTE (Sobre Carpinterías de Madera)', 'M2'),
  ('17', '17.5', 'PINTURA EPOXI / POLIURETÁNICA (Pisos Industriales / Garajes)', 'M2'),
  ('18', '18.1', 'INSTALACION ELECTRICIDAD', 'GL'),
  ('18', '18.2', 'INSTALACION GAS', 'GL'),
  ('18', '18.3', 'INSTALACION CALEFACCION', 'GL'),
  ('18', '18.4', 'INSTALACION SANITARIA AGUA CALIENTE Y FRIA', 'GL'),
  ('18', '18.5', 'INSTALACION SANITARIA CLOACAL', 'GL'),
  ('19', '19.1', 'CARPINTERIAS INTERIORES', 'GL'),
  ('19', '19.2', 'CARPINTERIAS EXTERIORES', 'GL'),
  ('20', '20.1', 'LIMPIEZA PERIODICA DE OBRA', 'GL'),
  ('20', '20.2', 'LIMPIEZA FINAL DE OBRA', 'GL')
) as v(rubro_codigo, codigo, descripcion, unidad)
join rubros r on r.codigo = v.rubro_codigo and r.creador_usuario_id is null;

-- =====================================================================
-- RLS — mismo patrón que rubros (0015_rubros.sql)
-- =====================================================================

alter table subitems enable row level security;

create policy subitems_select on subitems for select
using (
  creador_usuario_id is null
  or creador_usuario_id = auth.uid()
);

create policy subitems_insert on subitems for insert with check (
  creador_usuario_id = auth.uid()
);

create policy subitems_update on subitems for update using (
  creador_usuario_id = auth.uid()
) with check (
  creador_usuario_id = auth.uid()
);

create policy subitems_delete on subitems for delete using (
  creador_usuario_id = auth.uid()
);

-- Misma limitación conocida que rubros (0015_rubros.sql): el SELECT todavía no cubre
-- "colaborador con puede_ver_apu_ajena ve el subítem custom del dueño en su obra" — depende de
-- obra_subitems, que llega más adelante en el orden. Más restrictivo de lo que el diseño final
-- prevé, nunca menos.
