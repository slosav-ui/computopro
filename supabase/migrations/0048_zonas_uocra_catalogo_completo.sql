-- Costo de mano de obra — zonas UOCRA, catálogo completo. Ver
-- docs/costo_mano_de_obra_decisiones.md §15 para el diseño completo de esta tanda: por qué La
-- Pampa entra en Zona A, el aviso de "hay otras zonas sin cargar" del cartel, y los dos pasos que
-- quedan documentados sin código porque hoy son imposibles de verificar en el emulador (el gate
-- del alta de obra y la marca de La Pampa en el selector).
--
-- Solo suma las 3 zonas que faltaban al catálogo (Zona B ya estaba, 0045) — ninguna de las tres
-- tiene escala cargada todavía. No cambia el comportamiento del selector de zona del panel de
-- cargas sociales: sigue leyendo únicamente `escala_salarial_uocra`
-- (EscalaSalarialUocraRepository.getZonasDisponibles(), sin tocar en esta migración), así que
-- sigue mostrando solo Zona B hasta que se cargue la escala de alguna de estas tres.
--
-- Aplicar a mano en el SQL Editor de Supabase (Project → SQL Editor). No ejecutado
-- automáticamente por Claude Code: sin acceso a la base de datos desde este entorno.

insert into zonas_uocra (codigo, nombre, descripcion) values
  ('A', 'Zona A',
   'CABA y las provincias de Buenos Aires, Santiago del Estero, Santa Fe, Mendoza, San Juan, '
   'Catamarca, Córdoba, Entre Ríos, Salta, Tucumán, Chaco, San Luis, Corrientes, La Rioja, '
   'Formosa, Jujuy, La Pampa y Misiones'),
  ('C', 'Zona C', 'Santa Cruz'),
  ('CA', 'Zona C Austral', 'Tierra del Fuego');

-- La Pampa entra en Zona A por dos motivos, no uno — pesan igual, no es que el segundo sea un
-- desempate menor del primero:
--   1) Es la ubicación que más fuentes consultadas coinciden en darle. El texto del CCT 76/75 en
--      sí no se pudo verificar de forma directa: las tablas del acuerdo homologado publicado por
--      UOCRA vienen como imágenes dentro del PDF (ver 0045).
--   2) Zona A es la escala más barata de las cuatro. Si el usuario no corrige esto a mano, el
--      error queda del lado que no infla el presupuesto — con Zona B pasaría lo contrario.
-- Sigue sin verificar contra el texto del convenio. La marca de "a verificar" para La Pampa
-- (ítem marcado en la lista + nota al pie cuando se muestra Zona A) queda con su texto ya
-- redactado en docs/costo_mano_de_obra_decisiones.md §15, pero SIN CÓDIGO: hoy es inalcanzable en
-- el emulador, porque el selector solo ofrece zonas con escala cargada (únicamente B) — escribir
-- ese código ahora sería código sin forma de verificar. Se agrega cuando se cargue la escala de
-- Zona A.

-- FK de integridad: evita que `obra_presupuesto_config.zona_uocra` quede apuntando a un código
-- que no existe en el catálogo. No fuerza por sí sola que la zona tenga escala cargada (eso lo
-- sigue cubriendo el selector de UI, ver EscalaSalarialUocraRepository.getZonasDisponibles() y el
-- RAISE EXCEPTION de calcular_valor_hora_mano_obra, 0039) — mismo criterio que la FK equivalente
-- de escala_salarial_uocra.zona agregada en 0045.
alter table obra_presupuesto_config
  add constraint obra_presupuesto_config_zona_uocra_fkey
  foreign key (zona_uocra) references zonas_uocra(codigo);
