// Importador inteligente — el extractor. Ver docs/importador_inteligente_diagnostico.md.
//
// **Un solo extractor para las tres puertas.** Recibe una importación ya creada (archivo subido a
// Storage) y llena `importaciones_items`. De ahí en adelante no cambia nada: la pantalla de
// revisión y `confirmar_importacion` (0081) ya existen y no se enteran de quién llenó las filas.
//
// ================== POR QUÉ ESTO CORRE ACÁ Y NO EN EL CLIENTE ==================
//
// El importador de Excel de la ronda anterior se había movido al cliente a propósito, y el
// argumento estaba escrito en `importar-excel/index.ts`: sin IA no hay clave que proteger y sin
// límite que aplicar no hay nada que hacer cumplir del lado servidor.
//
// **Los dos motivos volvieron, que es exactamente lo que ese archivo anticipó.** Ahora hay una
// clave de API real que no puede viajar en el APK, y hay un costo por documento que se paga de una
// cuenta personal. El tope de la `0145` solo es un tope si se aplica donde el cliente no llega.
//
// ================== EL ORDEN DE LAS COSAS IMPORTA ==================
//
//   1. leer la importación CON LA AUTH DEL USUARIO  -> la RLS de la 0080 decide si puede o no;
//   2. **consumir el cupo** (0145)                  -> antes de gastar, no después;
//   3. recién ahí llamar al modelo.
//
// Si el paso 2 fuera después del 3, el documento número seis ya estaría pagado cuando se rechaza.
//
// ================== DESPLIEGUE (a mano, como las migraciones) ==================
//
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   supabase functions deploy leer-documento
//
// `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` ya las inyecta Supabase sola.
// No ejecutado automáticamente por Claude Code: sin acceso a la cuenta de Supabase desde este
// entorno, mismo motivo por el que las migraciones tampoco se aplican solas.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import * as XLSX from 'https://esm.sh/xlsx@0.18.5?target=deno';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Haiku 4.5: ~1 a 3 centavos de dólar por documento (§2 del diagnóstico). Variable de entorno y no
// constante para que probar Sonnet con un documento difícil sea `supabase secrets set` y no un
// deploy nuevo.
const MODELO = Deno.env.get('MODELO_IMPORTADOR') ?? 'claude-haiku-4-5';

// 97 partidas con su texto original entran cómodas. Si algún día un documento se corta a la mitad,
// el síntoma es `stop_reason: "max_tokens"` -- se revisa acá, no se adivina en la pantalla.
const MAX_TOKENS = 32000;

// ================== EL ESQUEMA DE SALIDA ==================
//
// `output_config.format` garantiza que la respuesta sea JSON válido contra este esquema -- no hace
// falta parsear texto libre ni pedirle por favor al modelo que no escriba nada alrededor.
//
// Sin `enum` en `moneda` a propósito: mezclar un enum con `null` en un esquema estricto es
// frágil, y el valor se valida abajo en tres líneas.
const ESQUEMA = {
  type: 'object',
  properties: {
    moneda: { type: ['string', 'null'] },
    total_declarado: { type: ['number', 'null'] },
    partidas: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          rubro: { type: ['string', 'null'] },
          descripcion: { type: 'string' },
          unidad: { type: ['string', 'null'] },
          cantidad: { type: ['number', 'null'] },
          precio_unitario: { type: ['number', 'null'] },
          confianza: { type: 'string', enum: ['alta', 'media', 'baja'] },
          texto_original: { type: ['string', 'null'] },
        },
        required: [
          'rubro',
          'descripcion',
          'unidad',
          'cantidad',
          'precio_unitario',
          'confianza',
          'texto_original',
        ],
        additionalProperties: false,
      },
    },
  },
  required: ['moneda', 'total_declarado', 'partidas'],
  additionalProperties: false,
};

// ================== LA CONSIGNA ==================
//
// Esto es la pieza, más que el código. Cada párrafo está por un error concreto:
//
// - "no es una partida" existe porque un subtotal de rubro parece una partida y entra sin ruido,
//   y después infla el presupuesto sin que nadie sepa de dónde salió.
// - el párrafo de los números existe por el error que el diagnóstico nombró: 410,96 -> 41096.
//   En Argentina el punto es separador de miles y la coma es el decimal, al revés de lo que el
//   modelo ve la mayor parte del tiempo.
// - "no inventes" existe porque un modelo completa huecos con algo plausible, que es justo el modo
//   de fallar más difícil de detectar mirando la pantalla.
const CONSIGNA = `Sos un lector de presupuestos de obra argentinos. Extraés las partidas de un documento tal como están, sin corregirlas ni completarlas.

QUÉ ES UNA PARTIDA
Una línea de trabajo con su descripción. Suele traer unidad, cantidad y precio unitario.

QUÉ NO ES UNA PARTIDA, y no va en la lista:
- subtotales por rubro, totales generales, IVA, anticipos;
- títulos de rubro sin cantidad ni precio (ese texto va en el campo "rubro" de las partidas que caen abajo);
- encabezados de tabla, números de página, datos del comitente, aclaraciones al pie.

NÚMEROS — leelos en formato argentino
El punto separa miles y la coma separa decimales. "1.234,56" es mil doscientos treinta y cuatro con cincuenta y seis. "410,96" es cuatrocientos diez con noventa y seis, NO cuarenta y un mil. Devolvé números JSON ya normalizados (1234.56).
Si un precio trae símbolo de moneda o espacios, sacalos. Si una cantidad trae la unidad pegada ("120 m2"), la cantidad es 120 y la unidad "m2".

NO INVENTES
Si un dato no está en el documento, poné null. Nunca lo deduzcas, ni lo calcules, ni lo completes con un valor razonable. Una partida sin precio es una partida sin precio.

CONFIANZA — una por partida, y es lo que decide qué revisa primero la persona
- "alta": los valores se leen sin ambigüedad.
- "media": hubo que interpretar algo (columnas corridas, texto partido en dos líneas, un número que podía leerse de dos formas).
- "baja": está borroso, cortado, ilegible o dudás de verdad.
Es mejor decir "media" de más que "alta" de más. Una fila marcada alta que estaba mal es el peor resultado posible, porque nadie la va a mirar.

TEXTO_ORIGINAL
La línea del documento tal como aparece, sin limpiar. Es lo que le permite a la persona comparar contra lo que interpretaste.

TOTAL_DECLARADO
El total que el documento imprime al pie. Copialo tal cual figura, sin recalcularlo ni sumarlo vos. Si el documento no trae un total, null.

MONEDA
"ARS" o "USD" según lo que diga el documento. Si no lo dice, null.`;

type Importacion = {
  id: string;
  archivo_nombre: string;
  archivo_storage_path: string;
  tipo_archivo: string;
  hojas_seleccionadas: string[] | null;
};

function tipoDeImagen(nombre: string): string {
  const ext = nombre.toLowerCase().split('.').pop() ?? '';
  if (ext === 'png') return 'image/png';
  if (ext === 'webp') return 'image/webp';
  if (ext === 'gif') return 'image/gif';
  return 'image/jpeg';
}

// btoa() sobre un string armado con spread revienta la pila con archivos grandes (un PDF de
// 5 MB son 5 millones de argumentos). De a bloques no.
function aBase64(bytes: Uint8Array): string {
  const BLOQUE = 0x8000;
  let binario = '';
  for (let i = 0; i < bytes.length; i += BLOQUE) {
    binario += String.fromCharCode(...bytes.subarray(i, i + BLOQUE));
  }
  return btoa(binario);
}

/// Excel entra como texto, no como archivo: el modelo no lee .xlsx, y no hace falta que lo lea.
/// Una planilla pasada a CSV conserva lo único que importa acá, que es qué valor está en qué
/// columna. Este camino corre SOLO cuando el parser determinístico del cliente no reconoció los
/// encabezados -- si los reconoció, la importación nunca llega a esta función.
function excelATexto(bytes: Uint8Array, hojas: string[] | null): string {
  const workbook = XLSX.read(bytes, { type: 'array' });
  const elegidas = hojas && hojas.length > 0 ? hojas : workbook.SheetNames;
  const partes: string[] = [];
  for (const nombre of elegidas) {
    const hoja = workbook.Sheets[nombre];
    if (!hoja) continue;
    partes.push(`### Hoja: ${nombre}\n${XLSX.utils.sheet_to_csv(hoja)}`);
  }
  return partes.join('\n\n');
}

function bloqueDelDocumento(
  importacion: Importacion,
  bytes: Uint8Array,
): Record<string, unknown> {
  switch (importacion.tipo_archivo) {
    case 'pdf':
      // Nativo, sin extraer texto primero. Eso es lo que disuelve el problema de que el proyecto
      // puede generar PDF y no leerlos (§3 del diagnóstico) -- y de paso conserva la disposición
      // visual de la tabla, que es justo la información que un extractor de texto tira.
      return {
        type: 'document',
        source: { type: 'base64', media_type: 'application/pdf', data: aBase64(bytes) },
      };
    case 'foto':
      return {
        type: 'image',
        source: {
          type: 'base64',
          media_type: tipoDeImagen(importacion.archivo_nombre),
          data: aBase64(bytes),
        },
      };
    case 'excel':
      return {
        type: 'text',
        text: excelATexto(bytes, importacion.hojas_seleccionadas),
      };
    default:
      throw new Error(`Tipo de archivo desconocido: ${importacion.tipo_archivo}`);
  }
}

function aNumeroONull(valor: unknown): number | null {
  return typeof valor === 'number' && Number.isFinite(valor) ? valor : null;
}

function aTextoONull(valor: unknown): string | null {
  if (typeof valor !== 'string') return null;
  const texto = valor.trim();
  return texto === '' ? null : texto;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });

  const jsonHeaders = { ...CORS_HEADERS, 'Content-Type': 'application/json' };
  const error = (mensaje: string, status = 400, codigo?: string) =>
    new Response(JSON.stringify({ error: mensaje, codigo }), { status, headers: jsonHeaders });

  let body: { importacion_id?: string };
  try {
    body = await req.json();
  } catch {
    return error('Cuerpo de la solicitud inválido, se esperaba JSON.');
  }
  const importacionId = body.importacion_id;
  if (!importacionId) return error('Falta importacion_id.');

  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) return error('El servidor no tiene configurada la clave del modelo.', 500);

  // Dos clientes, y la diferencia es deliberada.
  //
  // `usuario` reenvía el Authorization de quien llamó: todo lo que se lee y se escribe pasa por la
  // misma RLS de la 0080 que rige cuando la app toca esas tablas directo. No hay un chequeo de
  // autoridad aparte en este archivo, y no debería haberlo -- sería una segunda regla que se puede
  // desincronizar de la primera.
  //
  // `servicio` existe para UNA cosa: llamar al cupo, que está revocado a `authenticated` justamente
  // para que el cliente no pueda saltearlo. Es el privilegio más chico que hace falta.
  const usuario = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } },
  );
  const servicio = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  // --- 1. La importación, con la autoridad del que llama
  const { data: importacion, error: errImportacion } = await usuario
    .from('importaciones')
    .select('id, archivo_nombre, archivo_storage_path, tipo_archivo, hojas_seleccionadas')
    .eq('id', importacionId)
    .single();

  if (errImportacion || !importacion) {
    // "No encontrada" y "sin permiso" se ven igual desde acá adentro, y se responden igual: mismo
    // criterio fail-closed que el resto del proyecto.
    return error('Importación no encontrada o sin permiso.', 404);
  }

  // --- 2. El cupo, ANTES de gastar
  //
  // Si devuelve error, el mensaje que trae es el de la 0145 -- escrito para que lo lea una persona,
  // con el número, la fecha de reinicio y la salida por Excel. Se reenvía tal cual: reescribirlo
  // acá sería tener el mismo texto en dos lugares.
  const { error: errCupo } = await servicio.rpc('consumir_cupo_importacion_ia', {
    p_importacion_id: importacionId,
  });
  if (errCupo) {
    return error(errCupo.message, 429, 'cupo_agotado');
  }

  // --- 3. El archivo
  const { data: archivo, error: errArchivo } = await usuario.storage
    .from('importaciones')
    .download(importacion.archivo_storage_path);
  if (errArchivo || !archivo) {
    return error('No se pudo leer el archivo desde Storage.', 500);
  }
  const bytes = new Uint8Array(await archivo.arrayBuffer());

  let bloque: Record<string, unknown>;
  try {
    bloque = bloqueDelDocumento(importacion as Importacion, bytes);
  } catch (e) {
    return error(e instanceof Error ? e.message : 'No se pudo preparar el documento.', 422);
  }

  // --- 4. El modelo
  const respuesta = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: MODELO,
      max_tokens: MAX_TOKENS,
      system: CONSIGNA,
      messages: [
        {
          role: 'user',
          content: [
            bloque,
            { type: 'text', text: 'Extraé las partidas de este presupuesto.' },
          ],
        },
      ],
      output_config: { format: { type: 'json_schema', schema: ESQUEMA } },
    }),
  });

  if (!respuesta.ok) {
    const detalle = await respuesta.text();
    console.error('Error del modelo', respuesta.status, detalle);
    // El detalle NO va al usuario: puede traer información de la cuenta. Queda en los logs de la
    // función, que es donde se diagnostica.
    return error('No se pudo leer el documento. Probá de nuevo en un momento.', 502);
  }

  const mensaje = await respuesta.json();

  // Un documento que se cortó a la mitad es peor que uno que falló, porque parece completo. Se
  // corta acá y no se guarda nada.
  if (mensaje.stop_reason === 'max_tokens') {
    return error(
      'El documento es más largo de lo que se puede leer de una vez. Probá importarlo por partes.',
      422,
    );
  }

  const textoJson = (mensaje.content ?? []).find((b: { type: string }) => b.type === 'text')?.text;
  if (!textoJson) return error('El modelo no devolvió contenido legible.', 502);

  let salida: {
    moneda?: unknown;
    total_declarado?: unknown;
    partidas?: Array<Record<string, unknown>>;
  };
  try {
    salida = JSON.parse(textoJson);
  } catch {
    return error('El modelo devolvió algo que no se pudo interpretar.', 502);
  }

  const partidas = Array.isArray(salida.partidas) ? salida.partidas : [];
  if (partidas.length === 0) {
    return error(
      'No se encontraron partidas en el documento. Revisá que sea un presupuesto y que se lea bien.',
      422,
    );
  }

  // --- 5. A la base
  //
  // Se borran los ítems que hubiera antes: un reintento después de una falla a mitad de camino no
  // tiene que dejar las filas duplicadas. Va con `servicio` porque `importaciones_items` no tiene
  // política de DELETE a propósito (descartar una importación es un estado, no un borrado) -- y
  // esta no es esa operación, es limpiar un intento propio antes de reescribirlo. La autoridad ya
  // se verificó en el paso 1.
  await servicio.from('importaciones_items').delete().eq('importacion_id', importacionId);

  const moneda = salida.moneda === 'ARS' || salida.moneda === 'USD' ? salida.moneda : null;

  const filas = partidas.map((p, i) => ({
    importacion_id: importacionId,
    orden: i + 1,
    rubro_texto: aTextoONull(p.rubro),
    descripcion_texto: aTextoONull(p.descripcion) ?? '(sin descripción)',
    unidad_texto: aTextoONull(p.unidad),
    cantidad: aNumeroONull(p.cantidad),
    precio_unitario: aNumeroONull(p.precio_unitario),
    moneda,
    confianza: ['alta', 'media', 'baja'].includes(String(p.confianza)) ? p.confianza : 'baja',
    // El texto original va acá y no en una columna propia: `datos_originales` existe desde la 0080
    // justamente como respaldo de la fila cruda "para cuando el parser se equivocó y hay que
    // revisar el original". Es el mismo propósito, con otro lector.
    datos_originales: { texto_original: aTextoONull(p.texto_original), modelo: MODELO },
  }));

  const { error: errInsert } = await usuario.from('importaciones_items').insert(filas);
  if (errInsert) return error(errInsert.message, 500);

  // La confianza general de la importación es la PEOR de sus filas, no el promedio: sirve para
  // decidir cuánta atención pedir, y una sola fila dudosa ya es motivo para mirar con atención.
  const confianzaGeneral = filas.some((f) => f.confianza === 'baja')
    ? 'baja'
    : filas.some((f) => f.confianza === 'media')
      ? 'media'
      : 'alta';

  const uso = mensaje.usage ?? {};
  await usuario
    .from('importaciones')
    .update({
      total_declarado: aNumeroONull(salida.total_declarado),
      moneda_default: moneda,
      confianza_general: confianzaGeneral,
      modelo: MODELO,
      tokens_entrada: uso.input_tokens ?? null,
      tokens_salida: uso.output_tokens ?? null,
    })
    .eq('id', importacionId);

  return new Response(
    JSON.stringify({
      partidas: filas.length,
      confianza_general: confianzaGeneral,
      total_declarado: aNumeroONull(salida.total_declarado),
      moneda,
    }),
    { headers: jsonHeaders },
  );
});
