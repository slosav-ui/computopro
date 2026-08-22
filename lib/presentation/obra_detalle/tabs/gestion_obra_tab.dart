import 'package:flutter/material.dart';
import '../../../data/models/certificado.dart';
import '../../../services/certificados_repository.dart';

class GestionObraTab extends StatefulWidget {
  final String obraId;

  const GestionObraTab({Key? key, required this.obraId}) : super(key: key);

  @override
  State<GestionObraTab> createState() => _GestionObraTabState();
}

class _GestionObraTabState extends State<GestionObraTab> {
  final CertificadosRepository _certificadosRepository = CertificadosRepository();

  List<Certificado> _certificados = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCertificados();
  }

  Future<void> _cargarCertificados() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final certs = await _certificadosRepository.getCertificadosDeObra(widget.obraId);
      if (!mounted) return;
      setState(() {
        _certificados = certs;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los certificados de esta obra.';
        _cargando = false;
      });
    }
  }

  String _fmt(double monto) {
    final valorInt = monto.round();
    final str = valorInt.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formateado = str.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return '\$ $formateado';
  }

  String _fmtFecha(DateTime? fecha) {
    if (fecha == null) return '—';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  Color _getColorEstado(EstadoCertificado estado) {
    switch (estado) {
      case EstadoCertificado.borrador:
        return Colors.orange.shade700;
      case EstadoCertificado.emitido:
        return Colors.blue.shade700;
      case EstadoCertificado.leido:
        return Colors.indigo.shade700;
      case EstadoCertificado.pagado:
        return Colors.green.shade700;
      case EstadoCertificado.impactadoCerrado:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _cargarCertificados,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Historial de Certificados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B365D)),
            ),
            const SizedBox(height: 12),
            _buildContenido(),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 32),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }
    if (_certificados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.description_outlined, color: Colors.black26, size: 32),
              SizedBox(height: 8),
              Text(
                'Todavía no hay certificados cargados para esta obra.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _certificados.length,
      itemBuilder: (context, index) {
        final cert = _certificados[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Certificado Nº ${cert.numero.toString().padLeft(3, '0')} - ${cert.periodo}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B365D)),
                      ),
                    ),
                    Chip(
                      label: Text(
                        cert.estado.label,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: _getColorEstado(cert.estado),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Monto Certificado: ${_fmt(cert.monto)}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                Text(
                  'Emisión: ${_fmtFecha(cert.fechaEmision)}${cert.diasPlazoPago != null ? ' | Plazo: ${cert.diasPlazoPago} días' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
