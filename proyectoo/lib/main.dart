import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:pedometer/pedometer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math';
import 'package:open_file/open_file.dart';
import 'package:flutter/services.dart';

// ════════════════════════════════════════════════════════════════
//  API SERVICE
// ════════════════════════════════════════════════════════════════

class ApiService {
  //IPs
  static const String baseUrl = 'http://172.20.10.13:8000/api'; //telefono
  //static const String baseUrl = 'http://192.168.56.1:8000/api';  //UTT
  //static const String baseUrl = 'http://192.168.1.118:8000/api'; //Casa
  static String? _token;
  static int? _userId;
  static const _timeout = Duration(seconds: 10);

  static String get serverOrigin => Uri.parse(baseUrl).origin;

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Token $_token',
      };

  static String formatApiError(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['non_field_errors'] is List) {
          final l = decoded['non_field_errors'] as List;
          if (l.isNotEmpty) return l.first.toString();
        }
        final msgs = <String>[];
        for (final e in decoded.entries) {
          if (e.key == 'non_field_errors') continue;
          final v = e.value;
          if (v is List && v.isNotEmpty) msgs.add(v.first.toString());
          else if (v is String) msgs.add(v);
        }
        if (msgs.isNotEmpty) return msgs.join('\n');
        if (decoded['detail'] != null) {
          return decoded['detail'].toString();
        }
      }
    } catch (_) {}
    if (body.isEmpty) return 'Error del servidor';
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }

  static bool get estaLogueado => _token != null;
  static int? get userId => _userId;

  static void logout() {
    _token = null;
    _userId = null;
    borrarSesion();
  }

  // ── AUTH ─────────────────────────────────────────

  static Future<String?> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/login/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email.trim().toLowerCase(),
          'password': password,
        }),
      ).timeout(_timeout);
      print('STATUS: ${res.statusCode}');
      print('BODY: ${res.body}');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        _token = data['token'];
        _userId = data['user_id'];
        await guardarSesion();
        return null;
      }
      try {
        final b = json.decode(res.body);
        if (b is Map && b['detail'] != null) {
          return b['detail'].toString();
        }
      } catch (_) {}
      return 'Correo o contraseña incorrectos';
    } catch (e) {
      return 'Error de conexión: verifica que Django esté corriendo';
    }
  }

  static Future<String?> register({
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
    String? phone,
    String? firstName,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
          'password_confirm': passwordConfirm,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (firstName != null && firstName.trim().isNotEmpty)
            'first_name': firstName.trim(),
        }),
      ).timeout(_timeout);
      if (res.statusCode == 201) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        _token = data['token'] as String?;
        _userId = data['user_id'] as int?;
        return null;
      }
      final decoded = json.decode(res.body);
      if (decoded is Map<String, dynamic>) {
        final msgs = <String>[];
        for (final e in decoded.values) {
          if (e is List && e.isNotEmpty) {
            msgs.add(e.first.toString());
          } else if (e is String) {
            msgs.add(e);
          }
        }
        if (msgs.isNotEmpty) return msgs.join('\n');
        if (decoded['detail'] != null) {
          return decoded['detail'].toString();
        }
      }
      return 'No se pudo crear la cuenta';
    } catch (e) {
      return 'Error de conexión: verifica que Django esté corriendo';
    }
  }

  static Future<List<dynamic>> getServiciosConVets() async {
    final res = await http.get(
        Uri.parse('$baseUrl/servicios-con-vets/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error servicios: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getCitaDetalle(int id) async {
    final res = await http.get(
        Uri.parse('$baseUrl/citas/$id/detalle/'), headers: _headers).timeout(_timeout);
    print('CITA DETALLE STATUS: ${res.statusCode}');
    print('CITA DETALLE BODY: ${res.body.substring(0, min(200, res.body.length))}');
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error cita detalle: ${res.statusCode}');
  }

  static Future<List<dynamic>> getHistorialMedico() async {
    final res = await http.get(
        Uri.parse('$baseUrl/historial-medico/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error historial: ${res.statusCode}');
  }

  // ── MASCOTAS ─────────────────────────────────────

  static Future<List<dynamic>> getMascotas() async {
    final res = await http.get(
        Uri.parse('$baseUrl/mascotas/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error mascotas: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> crearMascota(
    Map<String, dynamic> data, {
    String? photoPath,
  }) async {
    if (photoPath != null) {
      final file = File(photoPath);
      if (file.existsSync()) {
        final req = http.MultipartRequest(
            'POST', Uri.parse('$baseUrl/mascotas/'));
        req.headers['Authorization'] = 'Token $_token';
        data.forEach((k, v) {
          if (v != null) req.fields[k] = v.toString();
        });
        req.files.add(
            await http.MultipartFile.fromPath('photo', photoPath));
        final streamed = await req.send().timeout(_timeout);
        final res = await http.Response.fromStream(streamed);
        if (res.statusCode == 201) {
          return json.decode(res.body) as Map<String, dynamic>;
        }
        throw Exception(formatApiError(res.body));
      }
    }
    final res = await http.post(Uri.parse('$baseUrl/mascotas/'),
        headers: _headers, body: json.encode(data)).timeout(_timeout);
    if (res.statusCode == 201) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    throw Exception(formatApiError(res.body));
  }

  static Future<Map<String, dynamic>> editarMascota(
    int id,
    Map<String, dynamic> data, {
    String? photoPath,
  }) async {
    if (photoPath != null) {
      final file = File(photoPath);
      if (file.existsSync()) {
        final req = http.MultipartRequest(
            'PATCH', Uri.parse('$baseUrl/mascotas/$id/'));
        req.headers['Authorization'] = 'Token $_token';
        data.forEach((k, v) {
          if (v != null) req.fields[k] = v.toString();
        });
        req.files.add(
            await http.MultipartFile.fromPath('photo', photoPath));
        final streamed = await req.send().timeout(_timeout);
        final res = await http.Response.fromStream(streamed);
        if (res.statusCode == 200) {
          return json.decode(res.body) as Map<String, dynamic>;
        }
        throw Exception(formatApiError(res.body));
      }
    }
    final res = await http.patch(Uri.parse('$baseUrl/mascotas/$id/'),
        headers: _headers, body: json.encode(data)).timeout(_timeout);
    if (res.statusCode == 200) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    throw Exception(formatApiError(res.body));
  }

  static Future<void> eliminarMascota(int id) async {
    final res = await http.delete(
        Uri.parse('$baseUrl/mascotas/$id/'), headers: _headers).timeout(_timeout);
    if (res.statusCode != 204) throw Exception('Error eliminar mascota');
  }

  // ── CITAS ─────────────────────────────────────────

  static Future<List<dynamic>> getCitas() async {
    final res = await http.get(
        Uri.parse('$baseUrl/citas/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error citas: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> crearCita(
      Map<String, dynamic> data) async {
    final res = await http.post(Uri.parse('$baseUrl/citas/'),
        headers: _headers, body: json.encode(data)).timeout(_timeout);
    if (res.statusCode == 201) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    throw Exception(formatApiError(res.body));
  }

  static Future<void> cancelarCita(int id) async {
    final res = await http.delete(
        Uri.parse('$baseUrl/citas/$id/'), headers: _headers).timeout(_timeout);
    if (res.statusCode != 204) throw Exception('Error cancelar cita');
  }

  // ── VETERINARIOS ─────────────────────────────────

  static Future<List<dynamic>> getVeterinarios() async {
    final res = await http.get(
        Uri.parse('$baseUrl/veterinarios/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error veterinarios: ${res.statusCode}');
  }

  static Future<List<String>> getAvailableSlots(int vetId, String date) async {
    final res = await http.get(
        Uri.parse('$baseUrl/available_slots/?vet_id=$vetId&date=$date'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      return List<String>.from(data['available_slots']);
    }
    throw Exception('Error available slots: ${res.statusCode}');
  }

  // ── CONSULTAS ────────────────────────────────────

  static Future<List<dynamic>> getConsultas() async {
    final res = await http.get(
        Uri.parse('$baseUrl/consultas/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error consultas: ${res.statusCode}');
  }

  // ── HOSPITALIZACIONES ────────────────────────────

  static Future<List<dynamic>> getHospitalizaciones() async {
    final res = await http.get(
        Uri.parse('$baseUrl/hospitalizaciones/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(utf8.decode(res.bodyBytes));
    throw Exception('Error hospitalizaciones: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> getHospitalizacionDetalle(int id) async {
    final res = await http.get(
        Uri.parse('$baseUrl/hospitalizaciones/$id/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(utf8.decode(res.bodyBytes));
    throw Exception('Error hospitalizacion detalle: ${res.statusCode}');
  }

  // ── PERFIL ───────────────────────────────────────

  static Future<List<dynamic>> getPerfiles() async {
    final res = await http.get(
        Uri.parse('$baseUrl/perfiles/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body);
    throw Exception('Error perfiles: ${res.statusCode}');
  }

  static Future<void> editarPerfil(
      int id, Map<String, dynamic> data) async {
    final res = await http.put(Uri.parse('$baseUrl/perfiles/$id/'),
        headers: _headers, body: json.encode(data)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception(formatApiError(res.body));
    }
  }

  static Future<void> updateAvatar(String imagePath) async {
    final uri = Uri.parse('$baseUrl/profile/avatar/');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Token $_token'; // solo este header
    request.files.add(await http.MultipartFile.fromPath('avatar', imagePath));
    final streamed = await request.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    print('AVATAR STATUS: ${res.statusCode}');
    print('AVATAR BODY: ${res.body}');
    if (res.statusCode != 200) {
      throw Exception('Error updating avatar: ${res.statusCode} ${res.body}');
    }
  }

  static Future<List<dynamic>> getHorariosClinica() async {
    final res = await http.get(
        Uri.parse('$baseUrl/horarios/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) return json.decode(res.body) as List<dynamic>;
    throw Exception(formatApiError(res.body));
  }

  static Future<Map<String, dynamic>> getMe() async {
    final res =
        await http.get(Uri.parse('$baseUrl/me/'), headers: _headers).timeout(_timeout);
    if (res.statusCode == 200) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    throw Exception(formatApiError(res.body));
  }

  static Future<Map<String, dynamic>> putMe(
      Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$baseUrl/me/'),
      headers: _headers,
      body: json.encode(data),
    ).timeout(_timeout);
    if (res.statusCode == 200) {
      return json.decode(res.body) as Map<String, dynamic>;
    }
    throw Exception(formatApiError(res.body));
  }

  static Future<void> guardarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token ?? '');
    await prefs.setInt('user_id', _userId ?? 0);
  }

  static Future<bool> cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final userId = prefs.getInt('user_id') ?? 0;
    if (token.isNotEmpty) {
      _token = token;
      _userId = userId;
      return true;
    }
    return false;
  }

  static Future<void> borrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
  }
}

// ════════════════════════════════════════════════════════════════
//  COLORES
// ════════════════════════════════════════════════════════════════

const kPrimary = Color(0xFF1565C0);
const kLight   = Color(0xFF42A5F5);
const kAccent  = Color(0xFF00B0FF);
const kBg      = Color(0xFFF4F6FB);
const kVacOk   = Color(0xFF2E7D32);
const kVacWarn = Color(0xFFEF6C00);
const kVacRisk = Color(0xFFC62828);

// ════════════════════════════════════════════════════════════════
//  MODELOS
// ════════════════════════════════════════════════════════════════

class AppNotificacion {
  final String id, titulo, cuerpo;
  final DateTime fecha;
  bool leida;
  final String tipo;

  AppNotificacion({
    required this.id, required this.titulo, required this.cuerpo,
    required this.fecha, required this.tipo, this.leida = false,
  });
}

class Usuario {
  final int id;
  String nombre, username, email;
  String? foto, telefono, direccion;
  int? perfilId;

  Usuario({
    required this.id, required this.nombre,
    required this.username, required this.email,
    this.foto, this.telefono, this.direccion, this.perfilId,
  });
}

class Veterinario {
  final int id;
  final String nombre, especialidad;
  final String? foto;

  Veterinario({
    required this.id, required this.nombre,
    required this.especialidad, this.foto,
  });

  factory Veterinario.fromJson(Map<String, dynamic> j) => Veterinario(
    id:           j['id'],
    nombre:       j['name'] ?? '',
    especialidad: j['get_specialty_display'] ?? j['specialty'] ?? '',
    foto:         j['photo'],
  );
}

class Mascota {
  final int id;
  String nombre, especie, raza, color;
  DateTime? fechaNacimiento;
  double peso;
  String? foto;
  String estadoVacunacion;
  String notasVacunas;

  Mascota({
    required this.id, required this.nombre,
    required this.especie, required this.raza,
    required this.peso, required this.color,
    this.fechaNacimiento,
    this.foto,
    this.estadoVacunacion = 'updated',
    this.notasVacunas = '',
  });

  // Edad calculada desde fechaNacimiento
  int get edad {
    if (fechaNacimiento == null) return 0;
    final hoy = DateTime.now();
    int e = hoy.year - fechaNacimiento!.year;
    if (hoy.month < fechaNacimiento!.month ||
        (hoy.month == fechaNacimiento!.month && hoy.day < fechaNacimiento!.day)) {
      e--;
    }
    return e;
  }

  factory Mascota.fromJson(Map<String, dynamic> j) => Mascota(
    id: j['id'],
    nombre: j['name'] ?? '',
    especie: j['pet_type'] ?? 'dog',
    raza: j['breed'] ?? '',
    fechaNacimiento: j['date_of_birth'] != null
        ? DateTime.tryParse(j['date_of_birth'])
        : null,
    peso: double.tryParse(j['weight'].toString()) ?? 0,
    color: j['color'] ?? '',
    foto: j['photo'],
    estadoVacunacion: j['vaccination_status'] ?? 'updated',
    notasVacunas: j['allergies'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': nombre,
    'pet_type': especie,
    'breed': raza,
    'date_of_birth': fechaNacimiento != null
        ? '${fechaNacimiento!.year}-${fechaNacimiento!.month.toString().padLeft(2,'0')}-${fechaNacimiento!.day.toString().padLeft(2,'0')}'
        : null,
    'weight': peso,
    'color': color,
    'vaccination_status': estadoVacunacion,
    'allergies': notasVacunas,
  };

  String? get fotoUrlAbsoluta {
    final p = foto;
    if (p == null || p.isEmpty) return null;
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    final o = ApiService.serverOrigin;
    return p.startsWith('/') ? '$o$p' : '$o/$p';
  }

  String get especieDisplay {
    const m = {'dog': 'Perro', 'cat': 'Gato', 'other': 'Otro'};
    return m[especie] ?? especie;
  }

  String get estadoVacunacionDisplay {
    const m = {
      'updated': 'Vacunas al día',
      'pending': 'Vacunas pendientes',
      'none': 'Sin vacunas registradas',
    };
    return m[estadoVacunacion] ?? estadoVacunacion;
  }
}

class Cita {
  final int id;
  int mascotaId;
  int? veterinarioId, servicioId;
  String estado, notas;
  DateTime fecha; // date + time combinados

  Cita({
    required this.id, required this.mascotaId, required this.fecha,
    this.veterinarioId, this.servicioId,
    this.estado = 'pending', this.notas = '',
  });

  factory Cita.fromJson(Map<String, dynamic> j) {
    final dateStr = j['date'] ?? '';
    final timeStr = j['time'] ?? '00:00:00';
    DateTime fecha;
    try {
      fecha = DateTime.parse('${dateStr}T$timeStr').toLocal();
    } catch (_) {
      fecha = DateTime.now();
    }
    return Cita(
      id: j['id'],
      mascotaId: j['pet'],
      fecha: fecha,
      veterinarioId: j['veterinarian'] ?? j['veterinarian_id'],
      servicioId: j['service'],
      estado: j['status'] ?? 'pending',
      notas: j['notes'] ?? '',
    );
  }

  // Estado en español
  String get estadoDisplay {
    const m = {
      'pending':   'Pendiente',
      'confirmed': 'Confirmada',
      'completed': 'Completada',
      'cancelled': 'Cancelada',
    };
    return m[estado] ?? estado;
  }

  Map<String, dynamic> toJson() => {
        'pet': mascotaId,
        'date':
            '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}',
        'time':
            '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}:00',
        'status': estado,
        'notes': notas,
        if (servicioId != null) 'service': servicioId,
        if (veterinarioId != null) 'veterinarian': veterinarioId,
      };
}

class VisitaMedica {
  final int id;
  final int citaId;
  final String diagnostico, tratamiento, motivo;
  final DateTime fecha;

  VisitaMedica({
    required this.id, required this.citaId, required this.fecha,
    required this.diagnostico, required this.tratamiento,
    required this.motivo,
  });

  factory VisitaMedica.fromJson(Map<String, dynamic> j) => VisitaMedica(
    id:           j['id'],
    citaId:       j['appointment'],
    fecha:        DateTime.parse(j['created_at']).toLocal(),
    diagnostico:  j['diagnosis']  ?? '',
    tratamiento:  j['treatment']  ?? '',
    motivo:       j['reason']     ?? '',
  );
}

class Servicio {
  final int id;
  final String nombre, descripcion, icono;
  final int duracion;
  final double precio;
  final List<Veterinario> veterinarios;

  Servicio({
    required this.id, required this.nombre,
    required this.descripcion, required this.icono,
    required this.duracion, required this.precio,
    required this.veterinarios,
  });

  factory Servicio.fromJson(Map<String, dynamic> j) => Servicio(
    id: j['id'],
    nombre: j['name'] ?? '',
    descripcion: j['description'] ?? '',
    icono: j['icon'] ?? '',
    duracion: j['duration'] ?? 0,
    precio: double.tryParse(j['price'].toString()) ?? 0,
    veterinarios: (j['veterinarios'] as List? ?? [])
        .map((v) => Veterinario.fromJson(v)).toList(),
  );
}

class ConsultaDetalle {
  final int id;
  final String diagnostico, tratamiento, motivo;
  final String? notas, peso, temperatura, proximaVisita;
  final RecetaDetalle? receta;

  ConsultaDetalle({
    required this.id, required this.diagnostico,
    required this.tratamiento, required this.motivo,
    this.notas, this.peso, this.temperatura,
    this.proximaVisita, this.receta,
  });

  factory ConsultaDetalle.fromJson(Map<String, dynamic> j) => ConsultaDetalle(
    id: j['id'],
    diagnostico: j['diagnostico'] ?? '',
    tratamiento: j['tratamiento'] ?? '',
    motivo: j['motivo'] ?? '',
    notas: j['notas'],
    peso: j['peso'],
    temperatura: j['temperatura'],
    proximaVisita: j['proxima_visita'],
    receta: j['receta'] != null ? RecetaDetalle.fromJson(j['receta']) : null,
  );
}

class RecetaDetalle {
  final int id;
  final String instrucciones;
  final String? advertencias;
  final List<MedicamentoItem> medicamentos;

  RecetaDetalle({
    required this.id, required this.instrucciones,
    this.advertencias, required this.medicamentos,
  });

  factory RecetaDetalle.fromJson(Map<String, dynamic> j) => RecetaDetalle(
    id: j['id'],
    instrucciones: j['instrucciones'] ?? '',
    advertencias: j['advertencias'],
    medicamentos: (j['medicamentos'] as List? ?? [])
        .map((m) => MedicamentoItem.fromJson(m)).toList(),
  );
}

class MedicamentoItem {
  final String medicamento, dosis, frecuencia, duracion;
  final String? instrucciones;

  MedicamentoItem({
    required this.medicamento, required this.dosis,
    required this.frecuencia, required this.duracion,
    this.instrucciones,
  });

  factory MedicamentoItem.fromJson(Map<String, dynamic> j) => MedicamentoItem(
    medicamento: j['medicamento'] ?? '',
    dosis: j['dosis'] ?? '',
    frecuencia: j['frecuencia'] ?? '',
    duracion: j['duracion'] ?? '',
    instrucciones: j['instrucciones'],
  );
}

class CitaCompleta extends Cita {
  final String? servicioNombre, veterinarioNombre, veterinarioFoto;
  final ConsultaDetalle? consulta;

  CitaCompleta({
    required super.id, required super.mascotaId, required super.fecha,
    super.veterinarioId, super.servicioId, super.estado, super.notas,
    this.servicioNombre, this.veterinarioNombre,
    this.veterinarioFoto, this.consulta,
  });

  factory CitaCompleta.fromJson(Map<String, dynamic> j) {
    final base = Cita.fromJson(j);
    return CitaCompleta(
      id: base.id, mascotaId: base.mascotaId, fecha: base.fecha,
      veterinarioId: base.veterinarioId, servicioId: base.servicioId,
      estado: base.estado, notas: base.notas,
      servicioNombre: j['servicio_nombre'],
      veterinarioNombre: j['veterinario_nombre'],
      veterinarioFoto: j['veterinario_foto'],
      consulta: j['consulta'] != null
          ? ConsultaDetalle.fromJson(j['consulta']) : null,
    );
  }
}

class Hospitalizacion {
  final int id;
  final int petId;
  final String petName, petType;
  final String? petPhoto, veterinarianName;
  final String reason, initialDiagnosis;
  final String status, statusDisplay, patientStatus, patientStatusDisplay;
  final String admissionDate;
  final String? dischargeDate, notes;
  final int monitoringCount;
  final List<dynamic> monitoring;
  final List<dynamic> treatments;
  final Map<String, dynamic>? order;

  Hospitalizacion({
    required this.id, required this.petId,
    required this.petName, required this.petType,
    this.petPhoto, this.veterinarianName,
    required this.reason, required this.initialDiagnosis,
    required this.status, required this.statusDisplay,
    required this.patientStatus, required this.patientStatusDisplay,
    required this.admissionDate,
    this.dischargeDate, this.notes,
    this.monitoringCount = 0,
    this.monitoring = const [],
    this.treatments = const [],
    this.order,
  });

  factory Hospitalizacion.fromJson(Map<String, dynamic> j) => Hospitalizacion(
    id: j['id'],
    petId: j['pet_id'],
    petName: j['pet_name'] ?? '',
    petType: j['pet_type'] ?? '',
    petPhoto: j['pet_photo'],
    veterinarianName: j['veterinarian_name'],
    reason: j['reason'] ?? '',
    initialDiagnosis: j['initial_diagnosis'] ?? '',
    status: j['status'] ?? '',
    statusDisplay: j['status_display'] ?? '',
    patientStatus: j['patient_status'] ?? '',
    patientStatusDisplay: j['patient_status_display'] ?? '',
    admissionDate: j['admission_date'] ?? '',
    dischargeDate: j['discharge_date'],
    notes: j['notes'],
    monitoringCount: j['monitoring_count'] ?? 0,
    monitoring: j['monitoring'] ?? [],
    treatments: j['treatments'] ?? [],
    order: j['order'],
  );
}

// ════════════════════════════════════════════════════════════════
//  PROVIDER
// ════════════════════════════════════════════════════════════════

class AppProvider with ChangeNotifier {
  List<Mascota> mascotas = [];
  List<Cita> citas = [];
  List<VisitaMedica> visitas = [];
  List<Veterinario> veterinarios = [];
  List<AppNotificacion> notificaciones = [];
  List<Servicio> servicios = [];
  List<CitaCompleta> historialMedico = [];
  List<Hospitalizacion> hospitalizaciones = [];
  /// Horarios de la clínica desde el API (RF-06)
  List<Map<String, dynamic>> horariosClinica = [];
  List<String> availableSlots = [];  // RF-06: Horarios disponibles
  Usuario? usuarioActual;
  bool cargando = false;

  int get notificacionesNoLeidas =>
      notificaciones.where((n) => !n.leida).length;

  // ── Auth ─────────────────────────────────────────

  Future<String?> login(String email, String password) async {
    try {
      final err = await ApiService.login(email, password);
      if (err != null) return err;
      final em = email.trim();
      usuarioActual = Usuario(
        id: ApiService.userId ?? 0,
        nombre: em.split('@').first,
        username: '',
        email: em,
      );
      await cargarTodo();
      return null;
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<String?> registrar({
    required String username,
    required String email,
    required String password,
    required String passwordConfirm,
    String? phone,
    String? firstName,
  }) async {
    try {
      final err = await ApiService.register(
        username: username,
        email: email,
        password: password,
        passwordConfirm: passwordConfirm,
        phone: phone,
      );
      if (err != null) return err;
      final nombreMostrar =
          (firstName != null && firstName.trim().isNotEmpty)
              ? firstName.trim()
              : username;
      usuarioActual = Usuario(
        id: ApiService.userId ?? 0,
        nombre: nombreMostrar,
        username: username,
        email: email,
        telefono: phone,
      );
      await cargarTodo();
      return null;
    } catch (e) {
      return 'Error: $e';
    }
  }

  Future<void> logout() async {
    ApiService.logout();
    usuarioActual = null;
    mascotas = []; citas = []; visitas = []; notificaciones = [];
    notifyListeners();
  }

  // ── Carga ─────────────────────────────────────────

  Future<void> cargarVeterinarios() async {
    try {
      final rows = await ApiService.getVeterinarios();
      veterinarios = rows.map((r) => Veterinario.fromJson(r)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error veterinarios: $e');
    }
  }

  Future<void> cargarAvailableSlots(int vetId, DateTime date) async {
    try {
      final dateStr = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
      availableSlots = await ApiService.getAvailableSlots(vetId, dateStr);
      notifyListeners();
    } catch (e) {
      debugPrint('Error available slots: $e');
      availableSlots = [];  // Fallback to empty
      notifyListeners();
    }
  }

  Future<void> cargarHorariosClinica() async {
    try {
      final rows = await ApiService.getHorariosClinica();
      horariosClinica =
          rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error horarios: $e');
    }
  }

  Future<void> syncPerfilDesdeApi() async {
    try {
      final me = await ApiService.getMe();
      final u = usuarioActual;
      if (u == null) return;

      final fn = (me['first_name'] as String?)?.trim() ?? '';
      if (fn.isNotEmpty) u.nombre = fn;

      final em = me['email'] as String? ?? '';
      if (em.isNotEmpty) u.email = em;

      final un = me['username'] as String? ?? '';
      if (un.isNotEmpty) u.username = un;

      u.telefono = me['phone'] as String? ?? '';
      u.direccion = me['address'] as String? ?? '';

      final pid = me['profile_id'];
      u.perfilId = pid is int ? pid : (pid is num ? pid.toInt() : null);

      final avatar = me['avatar'] as String?;
      if (avatar != null && avatar.isNotEmpty) u.foto = avatar;

      notifyListeners();
    } catch (e) {
      debugPrint('sync perfil error: $e');
      // No relanza el error — la app continúa sin perfil sincronizado
    }
  }

  Future<void> cargarTodo() async {
    cargando = true;
    notifyListeners();
    try {
      // Sync perfil con timeout propio
      await syncPerfilDesdeApi().timeout(
        const Duration(seconds: 8),
        onTimeout: () => debugPrint('syncPerfil timeout'),
      );

      // Cargar todo en paralelo con timeout global
      await Future.wait([
        cargarVeterinarios(),
        cargarHorariosClinica(),
        cargarServicios(),
        cargarHistorialMedico(),
        cargarHospitalizaciones(),
      ]).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint('carga paralela timeout');
          return <void>[];
        },
      );

      final results = await Future.wait([
        ApiService.getMascotas(),
        ApiService.getCitas(),
        ApiService.getConsultas(),
      ]).timeout(
        const Duration(seconds: 12),
        onTimeout: () => [[], [], []],
      );

      mascotas = results[0].map((r) => Mascota.fromJson(r)).toList();
      citas    = results[1].map((r) => Cita.fromJson(r)).toList();
      visitas  = results[2].map((r) => VisitaMedica.fromJson(r)).toList();

      generarNotificaciones();
    } catch (e) {
      debugPrint('Error cargarTodo: $e');
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> cargarHospitalizaciones() async {
    try {
      final rows = await ApiService.getHospitalizaciones();
      hospitalizaciones = rows.map((r) => Hospitalizacion.fromJson(r)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error hospitalizaciones: $e');
    }
  }

  // ── Notificaciones ───────────────────────────────

  void generarNotificaciones() {
    final ahora = DateTime.now();
    final nuevas = <AppNotificacion>[];
    for (final cita in citas) {
      if (cita.estado == 'cancelled') continue;
      final diff  = cita.fecha.difference(ahora);
      final dias  = diff.inDays;
      final horas = diff.inHours;
      String? titulo, cuerpo;
      if (horas >= 0 && horas <= 2) {
        titulo = '⏰ ¡Cita en menos de 2 horas!';
        cuerpo = 'A las ${cita.fecha.hour.toString().padLeft(2,'0')}:${cita.fecha.minute.toString().padLeft(2,'0')}';
      } else if (dias == 0) {
        titulo = '🐾 Tienes una cita hoy';
        cuerpo = 'A las ${cita.fecha.hour.toString().padLeft(2,'0')}:${cita.fecha.minute.toString().padLeft(2,'0')}';
      } else if (dias == 1) {
        titulo = '📅 Cita mañana';
        cuerpo = '${cita.fecha.day}/${cita.fecha.month}';
      } else if (dias <= 3) {
        titulo = '📆 Cita en $dias días';
        cuerpo = '${cita.fecha.day}/${cita.fecha.month}';
      }
      if (titulo != null) {
        final nId = 'cita_${cita.id}';
        if (!notificaciones.any((n) => n.id == nId)) {
          nuevas.add(AppNotificacion(
              id: nId, titulo: titulo, cuerpo: cuerpo!,
              fecha: ahora, tipo: 'cita'));
        }
      }
    }
    if (nuevas.isNotEmpty) {
      notificaciones.insertAll(0, nuevas);
      notifyListeners();
    }
  }

  void marcarTodasLeidas() {
    for (final n in notificaciones) { n.leida = true; }
    notifyListeners();
  }

  void marcarLeida(String id) {
    final i = notificaciones.indexWhere((n) => n.id == id);
    if (i != -1) { notificaciones[i].leida = true; notifyListeners(); }
  }

  // ── Mascotas ─────────────────────────────────────

  Future<String?> agregarMascota(Mascota m, {String? photoPath}) async {
    try {
      final row =
          await ApiService.crearMascota(m.toJson(), photoPath: photoPath);
      mascotas.add(Mascota.fromJson(row));
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> editarMascota(
    int id,
    String nombre, String especie, String raza,
    DateTime? fechaNacimiento, // ← reemplaza int edad
    double peso, String color, {
    String estadoVac = 'updated',
    String notasVac = '',
    String? photoPath,
  }) async {
    final fechaStr = fechaNacimiento != null
        ? '${fechaNacimiento.year}-${fechaNacimiento.month.toString().padLeft(2,'0')}-${fechaNacimiento.day.toString().padLeft(2,'0')}'
        : null;
    try {
      final data = await ApiService.editarMascota(
        id,
        {
          'name': nombre,
          'pet_type': especie,
          'breed': raza,
          if (fechaStr != null) 'date_of_birth': fechaStr,
          'weight': peso,
          'color': color,
          'vaccination_status': estadoVac,
          'allergies': notasVac,
        },
        photoPath: photoPath,
      );
      final i = mascotas.indexWhere((m) => m.id == id);
      if (i != -1) mascotas[i] = Mascota.fromJson(data);
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> eliminarMascota(int id) async {
    try {
      await ApiService.eliminarMascota(id);
      mascotas.removeWhere((m) => m.id == id);
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  // ── Citas ─────────────────────────────────────────

  Future<String?> agregarCita(Cita c) async {
    try {
      final row = await ApiService.crearCita(c.toJson());
      citas.add(Cita.fromJson(row));
      generarNotificaciones();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> cancelarCita(int id) async {
    try {
      await ApiService.cancelarCita(id);
      citas.removeWhere((c) => c.id == id);
      notificaciones.removeWhere((n) => n.id == 'cita_$id');
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// RF-07/RF-08: mismo veterinario y fecha/hora (y misma mascota en servidor)
  bool slotOcupado(int vetId, DateTime dia, int hora, int minuto) {
    return citas.any((c) =>
        c.veterinarioId == vetId &&
        c.estado != 'cancelled' &&
        c.fecha.year == dia.year &&
        c.fecha.month == dia.month &&
        c.fecha.day == dia.day &&
        c.fecha.hour == hora &&
        c.fecha.minute == minuto);
  }

  List<Cita> get citasFuturas {
    final ahora = DateTime.now();
    return citas.where((c) => c.fecha.isAfter(ahora)).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
  }

  // ── Visitas ───────────────────────────────────────

  List<VisitaMedica> visitasDeMascota(int mascotaId) {
    final citasIds = citas
        .where((c) => c.mascotaId == mascotaId)
        .map((c) => c.id)
        .toSet();
    return visitas.where((v) => citasIds.contains(v.citaId)).toList();
  }

  // ── Perfil ────────────────────────────────────────

  Future<String?> actualizarPerfil({
    required String nombre,
    required String email,
    String? tel,
    String? dir,
  }) async {
    try {
      await ApiService.putMe({
        'first_name': nombre,
        'email': email,
        'phone': tel ?? '',
        'address': dir ?? '',
      });
      usuarioActual?.nombre = nombre;
      usuarioActual?.email = email;
      usuarioActual?.telefono = tel;
      usuarioActual?.direccion = dir;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<void> cargarServicios() async {
    try {
      final rows = await ApiService.getServiciosConVets();
      servicios = rows.map((r) => Servicio.fromJson(r)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error servicios: $e');
    }
  }

  Future<void> cargarHistorialMedico() async {
    try {
      final rows = await ApiService.getHistorialMedico();
      historialMedico = rows.map((r) => CitaCompleta.fromJson(r)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error historial: $e');
    }
  }

  Future<CitaCompleta?> getCitaDetalle(int id) async {
    try {
      final data = await ApiService.getCitaDetalle(id);
      return CitaCompleta.fromJson(data);
    } catch (e) {
      debugPrint('Error getCitaDetalle: $e');
      return null;
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  SPLASH
// ════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() { super.initState(); _check(); }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final tieneSesion = await ApiService.cargarSesion();

    if (tieneSesion) {
      final app = Provider.of<AppProvider>(context, listen: false);
      
      // Crear usuario temporal para que no sea null
      app.usuarioActual = Usuario(
        id: ApiService.userId ?? 0,
        nombre: 'Cargando...',
        username: '',
        email: '',
      );
      
      // Timeout de seguridad — si cargarTodo tarda más de 15s igual navega
      await app.cargarTodo().timeout(
        const Duration(seconds: 15),
        onTimeout: () => debugPrint('cargarTodo splash timeout'),
      );

      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: kPrimary,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
}

// ════════════════════════════════════════════════════════════════
//  LOGIN
// ════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _uCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  bool _obs = true, _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [kPrimary, kLight],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 16,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/logo.png', height: 130),
                  const SizedBox(height: 12),
                  const Text('Bienvenido',
                      style: TextStyle(fontSize: 26,
                          fontWeight: FontWeight.bold, color: kPrimary)),
                  const SizedBox(height: 4),
                  const Text('Ingresa tu correo y contraseña',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _uCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Correo electrónico',
                      hintText: 'tu@correo.com',
                      prefixIcon:
                          const Icon(Icons.mail_outline_rounded, color: kPrimary),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: kPrimary, width: 2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _tfObs(_pCtrl, 'Contraseña', _obs,
                      () => setState(() => _obs = !_obs)),
                  const SizedBox(height: 22),
                  _loading
                      ? const CircularProgressIndicator(color: kPrimary)
                      : _priBtn('Iniciar sesión', () async {
                          final em = _uCtrl.text.trim();
                          if (em.isEmpty || _pCtrl.text.isEmpty) {
                            _snack(context, 'Completa todos los campos');
                            return;
                          }
                          if (!em.contains('@')) {
                            _snack(context, 'Introduce un correo válido');
                            return;
                          }
                          setState(() => _loading = true);
                          final app = Provider.of<AppProvider>(
                              context, listen: false);
                          final err = await app.login(
                              em, _pCtrl.text.trim());
                          if (!context.mounted) return;
                          setState(() => _loading = false);
                          if (err == null) {
                            Navigator.pushReplacement(context,
                                MaterialPageRoute(
                                    builder: (_) => const HomeScreen()));
                          } else {
                            _snack(context, err);
                          }
                        }),
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RegisterScreen()),
                    ),
                    child: const Text(
                      '¿No tienes cuenta? Crear cuenta',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.blue,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  REGISTRO
// ════════════════════════════════════════════════════════════════

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  bool _obs = true, _obs2 = true, _loading = false;

  @override
  void dispose() {
    for (final c in [
      _userCtrl,
      _emailCtrl,
      _telCtrl,
      _passCtrl,
      _pass2Ctrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimary, kLight],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 16,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios,
                              color: kPrimary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      const Text(
                        'Crear cuenta',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: kPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Regístrate para usar la clínica desde el móvil',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      _tf(_userCtrl, 'Nombre de usuario *', Icons.person_outline),
                      const SizedBox(height: 10),
                      _tf(_emailCtrl, 'Correo *', Icons.email_outlined),
                      const SizedBox(height: 10),
                      _tf(_telCtrl, 'Teléfono (opcional)', Icons.phone_outlined),
                      const SizedBox(height: 10),
                      _tfObs(_passCtrl, 'Contraseña (mín. 8) *', _obs,
                          () => setState(() => _obs = !_obs)),
                      const SizedBox(height: 10),
                      _tfObs(_pass2Ctrl, 'Confirmar contraseña *', _obs2,
                          () => setState(() => _obs2 = !_obs2)),
                      const SizedBox(height: 20),
                      _loading
                          ? const CircularProgressIndicator(color: kPrimary)
                          : _priBtn('Registrarme', () async {
                              final u = _userCtrl.text.trim();
                              final em = _emailCtrl.text.trim();
                              final p1 = _passCtrl.text;
                              final p2 = _pass2Ctrl.text;
                              if (u.isEmpty || em.isEmpty) {
                                _snack(context,
                                    'Usuario y correo son obligatorios');
                                return;
                              }
                              if (p1.length < 8) {
                                _snack(context,
                                    'La contraseña debe tener al menos 8 caracteres');
                                return;
                              }
                              if (p1 != p2) {
                                _snack(context, 'Las contraseñas no coinciden');
                                return;
                              }
                              setState(() => _loading = true);
                              final app = Provider.of<AppProvider>(
                                  context,
                                  listen: false);
                              final err = await app.registrar(
                                username: u,
                                email: em,
                                password: p1,
                                passwordConfirm: p2,
                                phone: _telCtrl.text.trim().isEmpty
                                    ? null
                                    : _telCtrl.text.trim(),
                              );
                              if (!context.mounted) return;
                              setState(() => _loading = false);
                              if (err == null) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const HomeScreen()),
                                  (_) => false,
                                );
                              } else {
                                _snack(context, err);
                              }
                            }),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Ya tengo cuenta · Iniciar sesión',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  NOTIFICACIONES
// ════════════════════════════════════════════════════════════════

class NotificacionesScreen extends StatelessWidget {
  const NotificacionesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Notificaciones'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
        actions: [
          if (app.notificaciones.isNotEmpty)
            TextButton(
              onPressed: app.marcarTodasLeidas,
              child: const Text('Marcar todas',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
        ],
      ),
      body: app.notificaciones.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.notifications_none,
                    color: kPrimary, size: 48),
              ),
              const SizedBox(height: 16),
              const Text('Sin notificaciones',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 6),
              Text('Aquí aparecerán recordatorios de citas',
                  style: TextStyle(fontSize: 13,
                      color: Colors.grey.shade500)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: app.notificaciones.length,
              itemBuilder: (_, i) {
                final n = app.notificaciones[i];
                return GestureDetector(
                  onTap: () => app.marcarLeida(n.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: n.leida
                          ? Colors.white
                          : const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: n.leida
                            ? Colors.grey.shade200
                            : kPrimary.withOpacity(0.3),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.event,
                              color: kPrimary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(n.titulo,
                              style: TextStyle(
                                  fontWeight: n.leida
                                      ? FontWeight.w500
                                      : FontWeight.bold,
                                  fontSize: 13)),
                          const SizedBox(height: 3),
                          Text(n.cuerpo,
                              style: TextStyle(fontSize: 12,
                                  color: Colors.grey.shade600)),
                        ])),
                        if (!n.leida)
                          Container(width: 8, height: 8,
                              decoration: const BoxDecoration(
                                  color: kPrimary,
                                  shape: BoxShape.circle)),
                      ]),
                    ),
                  ),
                );
              }),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  HOME
// ════════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  Timer? _refreshTimer;

  // cita
  DateTime  _fechaCita = DateTime.now();
  String    _horaCita  = '';
  int?      _mascotaCitaId;
  int?      _veterinarioCitaId;
  String    _notasCita = '';

  // mascota form
  final _mNom = TextEditingController();
  final _mRaz = TextEditingController();
  DateTime? _mFechaNac;
  final _mPes = TextEditingController();
  final _mCol = TextEditingController();
  final _mVacNotas = TextEditingController();
  String _mEsp = 'dog';
  String _mVacEst = 'updated';
  String? _mFotoPath;
  int _tipIdx = 0;
  final _picker = ImagePicker();

  static const _vacunasOpts = [
    {'val': 'updated', 'label': 'Vacunas al día'},
    {'val': 'pending', 'label': 'Vacunas pendientes'},
    {'val': 'none', 'label': 'Sin vacunas registradas'},
  ];

  static const _horarios = [
    '09:00','09:30','10:00','10:30','11:00','11:30',
    '15:00','15:30','16:00','16:30',
  ];

  static const _especies = [
    {'val': 'dog',   'label': 'Perro'},
    {'val': 'cat',   'label': 'Gato'},
    {'val': 'other', 'label': 'Otro'},
  ];

  static const _tips = [
    {'icon': Icons.water_drop, 'color': kAccent,
     'texto': 'Asegúrate de que tu mascota tenga agua fresca disponible todo el día.'},
    {'icon': Icons.directions_walk, 'color': Color(0xFF66BB6A),
     'texto': 'Los perros necesitan al menos 30 minutos de ejercicio diario.'},
    {'icon': Icons.vaccines, 'color': Color(0xFFAB47BC),
     'texto': 'Mantener las vacunas al día es la mejor forma de proteger a tu mascota.'},
    {'icon': Icons.favorite, 'color': Color(0xFFEF5350),
     'texto': 'El tiempo de calidad con tu mascota fortalece el vínculo entre ustedes.'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final app = Provider.of<AppProvider>(context, listen: false);
      app.cargarTodo();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    for (final c in [_mNom, _mRaz, _mPes, _mCol, _mVacNotas]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app     = Provider.of<AppProvider>(context);
    final u       = app.usuarioActual;
    final h       = DateTime.now().hour;
    final saludo  = h < 12 ? 'Buenos días' : h < 18 ? 'Buenas tardes' : 'Buenas noches';
    final noLeidas = app.notificacionesNoLeidas;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kPrimary, elevation: 0,
        automaticallyImplyLeading: false,
        title: GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => PerfilScreen(app: app))),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: Colors.white.withOpacity(0.2),
              ),
              child: ClipOval(
                child: u?.foto != null && u!.foto!.isNotEmpty
                    ? Image.network(
                        u.foto!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 20),
                      )
                    : const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(saludo, style: const TextStyle(
                  fontSize: 10, color: Colors.white70,
                  fontWeight: FontWeight.normal)),
              Text(u?.nombre.split(' ').first ?? 'Usuario',
                  style: const TextStyle(fontSize: 14,
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
          ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => app.cargarTodo(),
          ),
          Stack(children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined,
                  color: Colors.white, size: 26),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const NotificacionesScreen())),
            ),
            if (noLeidas > 0)
              Positioned(right: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(
                        minWidth: 16, minHeight: 16),
                    child: Text(noLeidas > 9 ? '9+' : '$noLeidas',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                  )),
          ]),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        _tabInicio(app),
        _tabCitas(app),
        _tabMascotas(app),
      ]),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: kPrimary,
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PasosScreen(app: app))),
        child: const Icon(Icons.directions_walk,
            color: Colors.white, size: 26),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8, color: Colors.white, elevation: 12,
        child: SizedBox(height: 60,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
            _nav(Icons.home_rounded,   'Inicio',   0),
            _nav(Icons.calendar_month, 'Citas',    1),
            const SizedBox(width: 48),
            _nav(Icons.pets_rounded,   'Mascotas', 2),
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => HistorialMedicoScreen(app: app))),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.history_edu_outlined,
                    color: Colors.grey.shade400, size: 24),
                const SizedBox(height: 2),
                Text('Historial',
                    style: TextStyle(fontSize: 10,
                        color: Colors.grey.shade400)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _nav(IconData icon, String label, int idx) {
    final sel = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon,
            color: sel ? kPrimary : Colors.grey.shade400, size: 24),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10,
            color: sel ? kPrimary : Colors.grey.shade400,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }

  // ══════════════ TAB INICIO ══════════════════════

  Widget _tabInicio(AppProvider app) {
    final proxima = app.citasFuturas.isNotEmpty
        ? app.citasFuturas.first : null;
    final tip = _tips[_tipIdx % _tips.length];

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        // Header stats
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          decoration: const BoxDecoration(color: kPrimary,
              borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Clínica Veterinaria',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              _stat(Icons.calendar_today, '${app.citas.length}', 'Citas',
                  onTap: () => setState(() => _tab = 1)),
              const SizedBox(width: 10),
              _stat(Icons.pets, '${app.mascotas.length}', 'Mascotas',
                  onTap: () => setState(() => _tab = 2)),
              const SizedBox(width: 10),
              _stat(Icons.local_hospital, '${app.visitas.length}', 'Visitas',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => HistorialMedicoScreen(app: app)))),
            ]),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            _secTitle('Próxima Cita'),
            const SizedBox(height: 10),
            proxima == null
                ? _emptyBox(Icons.event_available, 'Sin citas próximas',
                    'Agenda una cita desde la pestaña Citas')
                : GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CitaDetalleScreen(citaId: proxima.id),
                    )),
                    child: _proxCard(app, proxima),
                  ),

            const SizedBox(height: 24),
            _secTitle('Mis Mascotas'),
            const SizedBox(height: 10),
            app.mascotas.isEmpty
                ? _emptyBox(Icons.pets, 'Sin mascotas',
                    'Agrega tu primera mascota')
                : SizedBox(height: 92,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: app.mascotas.length,
                      itemBuilder: (_, i) {
                        final m = app.mascotas[i];
                        return GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => MascotaDetalleScreen(mascota: m),
                          )),
                          child: Container(
                            margin: const EdgeInsets.only(right: 14),
                            child: Column(children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: const Color(0xFFBBDEFB),
                                backgroundImage: m.fotoUrlAbsoluta != null
                                    ? NetworkImage(m.fotoUrlAbsoluta!) : null,
                                child: m.fotoUrlAbsoluta == null
                                    ? const Icon(Icons.pets, color: kPrimary, size: 26) : null,
                              ),
                              const SizedBox(height: 6),
                              Text(m.nombre,
                                  style: const TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        );
                      },
                    )),

            const SizedBox(height: 24),
            _secTitle('Consejo del día'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _tipIdx++),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(18),
                decoration: _cardDeco(),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (tip['color'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(tip['icon'] as IconData,
                        color: tip['color'] as Color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(tip['texto'] as String,
                        style: const TextStyle(fontSize: 13,
                            height: 1.45, color: Colors.black87)),
                    const SizedBox(height: 6),
                    Text('Toca para ver otro consejo',
                        style: TextStyle(fontSize: 11,
                            color: Colors.grey.shade400)),
                  ])),
                ]),
              ),
            ),

            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => ExpedienteScreen(app: app))),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.folder_shared,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Expediente Clínico',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('Ver y descargar historial en PDF',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios,
                      color: Colors.white70, size: 16),
                ]),
              ),
            ),

            const SizedBox(height: 16),
            _contactCard(),
            const SizedBox(height: 30),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(IconData icon, String val, String lbl, {VoidCallback? onTap}) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 4),
          Text(val, style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.bold, fontSize: 18)),
          Text(lbl, style: TextStyle(
              color: Colors.white.withOpacity(0.8), fontSize: 10)),
        ]),
      ),
    ),
  );

  Widget _proxCard(AppProvider app, Cita cita) {
    final m = app.mascotas
        .where((m) => m.id == cita.mascotaId)
        .firstOrNull;
    final diff  = cita.fecha.difference(DateTime.now());
    final dias  = diff.inDays;
    final horas = diff.inHours % 24;
    final cuenta = dias > 0 ? 'en $dias día${dias == 1 ? '' : 's'}'
        : horas > 0 ? 'en $horas hora${horas == 1 ? '' : 's'}' : 'Hoy';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPrimary, kAccent]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.event, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(cita.estado == 'pending' ? 'Cita pendiente' : cita.estadoDisplay,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text(m?.nombre ?? 'Mascota',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85), fontSize: 12)),
          Text(
            '${cita.fecha.day}/${cita.fecha.month}/${cita.fecha.year}  '
            '${cita.fecha.hour.toString().padLeft(2,'0')}:'
            '${cita.fecha.minute.toString().padLeft(2,'0')}',
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 12),
          ),
        ])),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20)),
            child: Text(cuenta,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
        ),
      ]),
    );
  }

  Widget _emptyBox(IconData icon, String title, String sub) =>
      Container(
        width: double.infinity, padding: const EdgeInsets.all(18),
        decoration: _cardDeco(),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: kPrimary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 3),
            Text(sub, style: TextStyle(
                fontSize: 12, color: Colors.grey.shade500)),
          ])),
        ]),
      );

  // ══════════════ TAB CITAS ═══════════════════════

  Widget _tabCitas(AppProvider app) {
  final citasActivas = app.citas
      .where((c) => c.estado != 'completed' && c.estado != 'cancelled')
      .toList();

  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Botón principal reservar
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Reservar Nueva Cita',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const ReservarCitaScreen(),
          )).then((_) => app.cargarTodo()),
        ),
      ),
      const SizedBox(height: 16),

      // Botones servicios y veterinarios
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          icon: const Icon(Icons.medical_services, size: 16),
          label: const Text('Servicios'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: kPrimary,
            side: const BorderSide(color: kPrimary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const ServiciosScreen(),
          )),
        )),
        const SizedBox(width: 12),
        Expanded(child: ElevatedButton.icon(
          icon: const Icon(Icons.person_outline, size: 16),
          label: const Text('Veterinarios'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white, foregroundColor: kPrimary,
            side: const BorderSide(color: kPrimary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const VeterinariosScreen(),
          )),
        )),
      ]),
      const SizedBox(height: 24),

      // Horarios de clínica
      if (app.horariosClinica.isNotEmpty) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: _cardDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.schedule, color: kPrimary, size: 20),
              const SizedBox(width: 8),
              const Text('Horarios de atención',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            ...app.horariosClinica.map((h) {
              final abierto = h['is_open'] == true;
              final nom = h['get_day_of_week_display'] ?? h['day_of_week']?.toString() ?? '';
              final txt = abierto
                  ? '${h['opening_time'] ?? ''} – ${h['closing_time'] ?? ''}'
                  : 'Cerrado';
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('$nom: $txt',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              );
            }),
          ]),
        ),
        const SizedBox(height: 16),
      ],

      // Lista de citas activas
      _secTitle('Mis Citas (${citasActivas.length})'),
      const SizedBox(height: 10),

      citasActivas.isEmpty
          ? _emptyBox(Icons.calendar_today, 'Sin citas activas',
              'Reserva tu primera cita con el botón de arriba')
          : Column(children: citasActivas.map((cita) {
              final m = app.mascotas.where((m) => m.id == cita.mascotaId).firstOrNull;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => CitaDetalleScreen(citaId: cita.id),
                )),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: _cardDeco(),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: kPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.event, color: kPrimary, size: 22),
                    ),
                    title: Text(m?.nombre ?? 'Mascota',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _colorEstado(cita.estado).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(cita.estadoDisplay,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                color: _colorEstado(cita.estado))),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cita.fecha.day}/${cita.fecha.month}/${cita.fecha.year}  '
                        '${cita.fecha.hour.toString().padLeft(2,'0')}:'
                        '${cita.fecha.minute.toString().padLeft(2,'0')}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ]),
                    trailing: IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 22),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Cancelar cita'),
                            content: const Text('¿Seguro que deseas cancelar esta cita?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false),
                                  child: const Text('No')),
                              TextButton(onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Sí, cancelar',
                                      style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (ok == true) {
                          final ce = await app.cancelarCita(cita.id);
                          if (context.mounted && ce != null) _snack(context, ce);
                        }
                      },
                    ),
                  ),
                ),
              );
            }).toList()),
      const SizedBox(height: 24),
    ]),
  );
}

Color _colorEstado(String estado) {
  switch (estado) {
    case 'confirmed': return Colors.blue;
    case 'completed': return Colors.green;
    case 'cancelled': return Colors.red;
    default: return Colors.orange;
  }
}

  Widget _registroMascotaHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), kPrimary, kLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.pets_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nueva mascota',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Datos, vacunación y foto se guardan en tu expediente',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtituloSeccion(String titulo, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: kPrimary),
          const SizedBox(width: 8),
          Text(
            titulo,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _areaFotoMascotaRegistro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _subtituloSeccion('Foto de la mascota', Icons.photo_camera_rounded),
        Material(
          color: Colors.transparent,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _mFotoPath != null
                    ? kPrimary.withValues(alpha: 0.35)
                    : Colors.grey.shade300,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _mFotoPath != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(_mFotoPath!),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Material(
                          color: Colors.black54,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 22),
                            onPressed: () =>
                                setState(() => _mFotoPath = null),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          color: Colors.black45,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  final x = await _picker.pickImage(
                                      source: ImageSource.gallery);
                                  if (x != null) {
                                    setState(() => _mFotoPath = x.path);
                                  }
                                },
                                icon: const Icon(Icons.photo_library_rounded,
                                    color: Colors.white, size: 20),
                                label: const Text('Galería',
                                    style: TextStyle(color: Colors.white)),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final x = await _picker.pickImage(
                                      source: ImageSource.camera);
                                  if (x != null) {
                                    setState(() => _mFotoPath = x.path);
                                  }
                                },
                                icon: const Icon(Icons.camera_alt_rounded,
                                    color: Colors.white, size: 20),
                                label: const Text('Cámara',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_rounded,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      Text(
                        'Añade una foto',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Opcional · se sube al guardar',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final x = await _picker.pickImage(
                                  source: ImageSource.gallery);
                              if (x != null) {
                                setState(() => _mFotoPath = x.path);
                              }
                            },
                            icon: const Icon(Icons.photo_library_rounded),
                            label: const Text('Galería'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final x = await _picker.pickImage(
                                  source: ImageSource.camera);
                              if (x != null) {
                                setState(() => _mFotoPath = x.path);
                              }
                            },
                            icon: const Icon(Icons.camera_alt_rounded),
                            label: const Text('Cámara'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _panelVacunacionRegistro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE8F5E9),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF81C784).withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: kVacOk.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.vaccines_rounded,
                    color: Colors.green.shade800, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vacunación',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.green.shade900,
                      ),
                    ),
                    Text(
                      'Estado actual y registro de dosis o tratamientos',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '¿Cómo va su cartilla?',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _vacunasOpts.map((o) {
              final val = o['val']! as String;
              final sel = _mVacEst == val;
              final Color tint = val == 'updated'
                  ? kVacOk
                  : val == 'pending'
                      ? kVacWarn
                      : kVacRisk;
              return ChoiceChip(
                label: Text(
                  o['label']! as String,
                  style: const TextStyle(fontSize: 12.5),
                ),
                selected: sel,
                onSelected: (_) => setState(() => _mVacEst = val),
                selectedColor: tint.withValues(alpha: 0.22),
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: sel ? tint : Colors.grey.shade800,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(
                  color: sel ? tint : Colors.grey.shade300,
                  width: sel ? 1.8 : 1,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _mVacNotas,
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Vacunas y tratamientos (detalle)',
              hintText:
                  'Ej. Rabia — abril 2025 · Desparasitación interna…',
              alignLabelWithHint: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(Icons.note_alt_rounded,
                  color: Colors.green.shade700, size: 22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: Colors.green.shade600, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════ TAB MASCOTAS ════════════════════

  Widget _tabMascotas(AppProvider app) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Botón agregar
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Agregar Mascota',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _formRegistroMascota(app),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Lista mascotas
          app.mascotas.isEmpty
              ? _emptyBox(Icons.pets_rounded, 'Aún no hay mascotas',
                  'Agrega la primera con el botón de arriba')
              : Column(children: app.mascotas.map((m) => GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => MascotaDetalleScreen(mascota: m),
                  )),
                  child: _mascotaCard(app, m),
                )).toList()),
        ],
      ),
    );
  }

  Widget _formRegistroMascota(AppProvider app) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => StatefulBuilder( // ← agrega esto
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            controller: ctrl,
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            _registroMascotaHeader(),
            const SizedBox(height: 16),
            Container(
              decoration: _cardDeco(),
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                _subtituloSeccion('Datos generales', Icons.badge_outlined),
                _tf(_mNom, 'Nombre *', Icons.pets_rounded),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _mEsp,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Especie', filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
                  items: _especies.map((e) => DropdownMenuItem(value: e['val'], child: Text(e['label']!))).toList(),
                  onChanged: (v) => setState(() => _mEsp = v ?? 'dog'),
                  borderRadius: BorderRadius.circular(14),
                ),
                const SizedBox(height: 12),
                _tf(_mRaz, 'Raza', Icons.info_outline_rounded),
                const SizedBox(height: 12),
                Column(children: [
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _mFechaNac ?? DateTime.now().subtract(const Duration(days: 365)),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        helpText: 'Fecha de nacimiento',
                      );
                      if (picked != null) {
                        setState(() => _mFechaNac = picked);       // actualiza HomeScreen
                        setSheetState(() => _mFechaNac = picked);  // actualiza el sheet
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(children: [
                        Icon(Icons.cake_rounded, color: kPrimary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _mFechaNac != null
                                ? '${_mFechaNac!.day}/${_mFechaNac!.month}/${_mFechaNac!.year}'
                                : 'Fecha de nacimiento (opcional)',
                            style: TextStyle(
                              fontSize: 14,
                              color: _mFechaNac != null ? Colors.black87 : Colors.grey.shade500,
                            ),
                          ),
                        ),
                        if (_mFechaNac != null)
                          GestureDetector(
                            onTap: () {
                              setState(() => _mFechaNac = null);
                              setSheetState(() => _mFechaNac = null);
                            },
                            child: Icon(Icons.clear, color: Colors.grey.shade400, size: 18),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _tf(_mPes, 'Peso (kg)', Icons.monitor_weight_rounded),
                ]),
                const SizedBox(height: 12),
                _tf(_mCol, 'Color', Icons.palette_outlined),
                const SizedBox(height: 22),
                _areaFotoMascotaRegistro(),
                const SizedBox(height: 22),
                _panelVacunacionRegistro(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 54,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (_mNom.text.isEmpty) { _snack(context, 'El nombre es obligatorio'); return; }
                      final peso = double.tryParse(_mPes.text.replaceAll(',', '.'));
                      if (peso == null || peso <= 0) { _snack(context, 'Peso inválido'); return; }
                      final err = await app.agregarMascota(
                        Mascota(
                          id: 0,
                          nombre: _mNom.text.trim(),
                          especie: _mEsp,
                          raza: _mRaz.text.trim(),
                          fechaNacimiento: _mFechaNac,
                          peso: peso,
                          color: _mCol.text.trim(),
                          estadoVacunacion: _mVacEst,
                          notasVacunas: _mVacNotas.text.trim(),
                        ),
                        photoPath: _mFotoPath,
                      );
                      if (!context.mounted) return;
                      if (err != null) { _snack(context, err); return; }
                      for (final c in [_mNom, _mRaz, _mPes, _mCol, _mVacNotas]) c.clear();
                      setState(() { _mEsp = 'dog'; _mVacEst = 'updated'; _mFotoPath = null; _mFechaNac = null; });
                      Navigator.pop(context);
                      _snack(context, 'Mascota guardada');
                    },
                    icon: const Icon(Icons.save_rounded, size: 22),
                    label: const Text('Guardar mascota',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(backgroundColor: kPrimary, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    ));
  }

  Widget _avatarMascota(Mascota m, {double size = 52}) {
    final url = m.fotoUrlAbsoluta;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: const Color(0xFFE3F2FD),
                  child: Icon(Icons.pets_rounded, color: kPrimary, size: size * 0.45),
                ),
              )
            : ColoredBox(
                color: const Color(0xFFE3F2FD),
                child: Icon(Icons.pets_rounded, color: kPrimary, size: size * 0.45),
              ),
      ),
    );
  }

  Widget _mascotaCard(AppProvider app, Mascota m) {
    final visitas = app.visitasDeMascota(m.id);
    return Card(
      elevation: 2,
      shadowColor: Colors.black26,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: _avatarMascota(m),
        title: Text(
          m.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${m.especieDisplay} · ${m.raza} · ${m.edad} años',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                color: kPrimary, size: 20),
            onPressed: () => _dlgEditarMascota(app, m),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.red, size: 20),
            onPressed: () => _dlgEliminar(app, m),
          ),
        ]),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chipInfo('Edad: ${m.edad} años'),
                  _chipInfo('Peso: ${m.peso} kg'),
                  _chipInfo('Color: ${m.color}'),
                  _chipVacuna(m.estadoVacunacion, m.estadoVacunacionDisplay),
                ],
              ),
              if (m.notasVacunas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.green.shade200.withValues(alpha: 0.8)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.vaccines_rounded,
                          size: 20, color: Colors.green.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vacunas y tratamientos',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.green.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              m.notasVacunas,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              Text('Historial de Visitas',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700, fontSize: 13)),
              const SizedBox(height: 8),
              visitas.isEmpty
                  ? Text('Sin visitas registradas',
                      style: TextStyle(color: Colors.grey.shade400,
                          fontSize: 12))
                  : Column(children: visitas.map((v) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFE3F2FD),
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(v.diagnostico,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                          Text(v.tratamiento,
                              style: TextStyle(fontSize: 11,
                                  color: Colors.grey.shade600)),
                          Text(
                            '${v.fecha.day}/${v.fecha.month}/${v.fecha.year}',
                            style: TextStyle(fontSize: 10,
                                color: Colors.grey.shade400),
                          ),
                        ]),
                      )).toList()),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(String txt) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          txt,
          style: const TextStyle(fontSize: 11.5, color: kPrimary),
        ),
      );

  Widget _chipVacuna(String codigo, String texto) {
    final Color c = codigo == 'updated'
        ? kVacOk
        : codigo == 'pending'
            ? kVacWarn
            : kVacRisk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 14,
            color: c,
          ),
          const SizedBox(width: 4),
          Text(
            texto,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  void _dlgEliminar(AppProvider app, Mascota m) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar mascota'),
        content: Text('¿Seguro que deseas eliminar a ${m.nombre}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await app.eliminarMascota(m.id);
              if (!context.mounted) return;
              if (err != null) _snack(context, err);
            },
            child: const Text('Eliminar',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _dlgEditarMascota(AppProvider app, Mascota m) {
    final nom = TextEditingController(text: m.nombre);
    final raz = TextEditingController(text: m.raza);
    DateTime? fechaNac = m.fechaNacimiento;
    final pes = TextEditingController(text: '${m.peso}');
    final col = TextEditingController(text: m.color);
    final vacN = TextEditingController(text: m.notasVacunas);
    String esp = m.especie;
    String vacE = m.estadoVacunacion;
    String? fotoNueva;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Row(
            children: [
              Icon(Icons.edit_rounded, color: kPrimary, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Editar ${m.nombre}',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Foto',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: fotoNueva != null
                          ? Image.file(File(fotoNueva!), fit: BoxFit.cover)
                          : (m.fotoUrlAbsoluta != null
                              ? Image.network(
                                  m.fotoUrlAbsoluta!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                    color: const Color(0xFFE3F2FD),
                                    child: Icon(Icons.pets_rounded,
                                        color: kPrimary, size: 48),
                                  ),
                                )
                              : ColoredBox(
                                  color: const Color(0xFFE3F2FD),
                                  child: Center(
                                    child: Icon(Icons.pets_rounded,
                                        color: kPrimary, size: 52),
                                  ),
                                )),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final x = await _picker.pickImage(
                                source: ImageSource.gallery);
                            if (x != null) {
                              setSt(() => fotoNueva = x.path);
                            }
                          },
                          icon: const Icon(Icons.photo_library_rounded, size: 18),
                          label: const Text('Galería'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final x = await _picker.pickImage(
                                source: ImageSource.camera);
                            if (x != null) {
                              setSt(() => fotoNueva = x.path);
                            }
                          },
                          icon: const Icon(Icons.camera_alt_rounded, size: 18),
                          label: const Text('Cámara'),
                        ),
                      ),
                    ],
                  ),
                  if (fotoNueva != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setSt(() => fotoNueva = null),
                        child: const Text('Quitar foto nueva'),
                      ),
                    ),
                  const Divider(height: 28),
                  TextField(
                    controller: nom,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: esp,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Especie',
                      border: OutlineInputBorder(),
                    ),
                    items: _especies
                        .map((e) => DropdownMenuItem(
                              value: e['val']! as String,
                              child: Text(e['label']! as String),
                            ))
                        .toList(),
                    onChanged: (v) => setSt(() => esp = v ?? 'dog'),
                  ),
                  TextField(
                    controller: raz,
                    decoration: const InputDecoration(
                      labelText: 'Raza',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: fechaNac ?? DateTime.now().subtract(const Duration(days: 365)),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setSt(() => fechaNac = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.cake_rounded, color: kPrimary, size: 18),
                        const SizedBox(width: 8),
                        Text( 
                          fechaNac != null
                              ? '${fechaNac!.day}/${fechaNac!.month}/${fechaNac!.year}'
                              : 'Fecha de nacimiento',
                          style: TextStyle(
                            fontSize: 14,
                            color: fechaNac != null ? Colors.black87 : Colors.grey,
                          ),
                        ),
                      ]),
                    ),
                  ),
                  TextField(
                    controller: pes,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Peso (kg)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  TextField(
                    controller: col,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Vacunación',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _vacunasOpts.map((o) {
                      final val = o['val']! as String;
                      final sel = vacE == val;
                      final Color tint = val == 'updated'
                          ? kVacOk
                          : val == 'pending'
                              ? kVacWarn
                              : kVacRisk;
                      return ChoiceChip(
                        label: Text(o['label']! as String, style: const TextStyle(fontSize: 11)),
                        selected: sel,
                        onSelected: (_) => setSt(() => vacE = val),
                        selectedColor: tint.withValues(alpha: 0.2),
                        side: BorderSide(color: sel ? tint : Colors.grey.shade300),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: vacN,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Vacunas / tratamientos',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.note_alt_rounded,
                          color: Colors.green.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                nom.dispose();
                raz.dispose();
                pes.dispose();
                col.dispose();
                vacN.dispose();
                Navigator.pop(ctx);
              },
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final pe = double.tryParse(pes.text.replaceAll(',', '.'));
                if (pe == null || pe <= 0) {
                  _snack(ctx, 'Peso debe ser válido');
                  return;
                }
                final err = await app.editarMascota(
                  m.id,
                  nom.text.trim(), esp, raz.text.trim(),
                  fechaNac,
                  pe, col.text.trim(),
                  estadoVac: vacE,
                  notasVac: vacN.text.trim(),
                  photoPath: fotoNueva,
                );
                if (!ctx.mounted) return;
                nom.dispose();
                raz.dispose();
                pes.dispose();
                col.dispose();
                vacN.dispose();
                Navigator.pop(ctx);
                if (!context.mounted) return;
                if (err != null) {
                  _snack(context, err);
                } else {
                  _snack(context, 'Cambios guardados');
                }
              },
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════ CONTACTO ════════════════════════

  Widget _contactCard() => Container(
    decoration: _cardDeco(),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.local_hospital,
                color: kPrimary, size: 26),
          ),
          const SizedBox(width: 14),
          const Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Clínica Veterinaria',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('Lunes a Sábado  9:00 - 17:00',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _cBtn(Icons.phone_outlined, 'Llamar', Colors.green,
              () => _launch('tel:6648094202')),
          _cBtn(Icons.chat_outlined, 'WhatsApp', Colors.teal,
              () => _launch('https://wa.me/6648094202')),
          _cBtn(Icons.email_outlined, 'Email', kPrimary,
              () => _launch('mailto:clinica@vet.com')),
          _cBtn(Icons.location_on, 'Mapa', Colors.orange,
              () => _launch(
                  'https://maps.google.com/?q=Clinica+Veterinaria+Tijuana')),
        ]),
      ]),
    ),
  );

  Widget _cBtn(IconData icon, String label, Color color,
      VoidCallback fn) =>
      GestureDetector(
        onTap: fn,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(fontSize: 10,
              color: color, fontWeight: FontWeight.w600)),
        ]),
      );

  Future<void> _launch(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Widget _secTitle(String t) => Text(t,
      style: const TextStyle(fontSize: 16,
          fontWeight: FontWeight.bold, color: Colors.black87));

  Widget _drop<T>({
    required T? value, required String label, required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) =>
      Container(
        decoration: _cardDeco(),
        child: DropdownButtonFormField<T>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: kPrimary),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            filled: true, fillColor: Colors.white,
          ),
          items: items, onChanged: onChanged,
          borderRadius: BorderRadius.circular(14),
        ),
      );
}

// ════════════════════════════════════════════════════════════════
//  PERFIL
// ════════════════════════════════════════════════════════════════

class PerfilScreen extends StatefulWidget {
  final AppProvider app;
  const PerfilScreen({Key? key, required this.app}) : super(key: key);
  @override State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  late final TextEditingController _pNom;
  late final TextEditingController _pEma;
  late final TextEditingController _pTel;
  late final TextEditingController _pDir;
  String? _fotoLocal;

  @override
  void initState() {
    super.initState();
    final u = widget.app.usuarioActual;
    _pNom = TextEditingController(text: u?.nombre ?? '');
    _pEma = TextEditingController(text: u?.email ?? '');
    _pTel = TextEditingController(text: u?.telefono ?? '');
    _pDir = TextEditingController(text: u?.direccion ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final me = await ApiService.getMe();
        if (!mounted) return;
        setState(() {
          final fn = '${me['first_name'] ?? ''}'.trim();
          if (fn.isNotEmpty) _pNom.text = fn;
          final em = '${me['email'] ?? ''}'.trim();
          if (em.isNotEmpty) _pEma.text = em;
          _pTel.text = '${me['phone'] ?? ''}';
          _pDir.text = '${me['address'] ?? ''}';
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    for (final c in [_pNom, _pEma, _pTel, _pDir]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 80);
    if (pickedFile != null) {
      try {
        await ApiService.updateAvatar(pickedFile.path);
        if (!mounted) return;
        setState(() {
          _fotoLocal = pickedFile.path;
          widget.app.usuarioActual?.foto = pickedFile.path;
        });
        _snack(context, 'Foto de perfil actualizada');
      } catch (e) {
        if (!mounted) return;
        _snack(context, 'Error al actualizar foto: $e');
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar imagen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Cámara'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final u   = app.usuarioActual;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () async {
              await app.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false);
            },
            icon: const Icon(Icons.logout,
                color: Colors.white70, size: 18),
            label: const Text('Salir',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: _cardDeco(),
            child: Column(children: [
              GestureDetector(
                onTap: _showImageSourceDialog,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor: const Color(0xFFE3F2FD),
                      backgroundImage: _fotoLocal != null
                          ? FileImage(File(_fotoLocal!)) as ImageProvider
                          : (u?.foto != null && u!.foto!.isNotEmpty
                              ? NetworkImage(u!.foto!) as ImageProvider
                              : null),
                      child: (_fotoLocal == null && (u?.foto == null || u!.foto!.isEmpty))
                          ? const Icon(Icons.person, size: 50, color: kPrimary)
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: kPrimary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(u?.nombre ?? 'Usuario',
                  style: const TextStyle(fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(u?.username ?? '',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _statChip(Icons.pets, '${app.mascotas.length}', 'mascotas'),
                const SizedBox(width: 12),
                _statChip(Icons.calendar_today,
                    '${app.citas.length}', 'citas'),
              ]),
            ]),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20), decoration: _cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Información Personal',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 15, color: kPrimary)),
              const SizedBox(height: 16),
              _tf(_pNom, 'Nombre', Icons.person_outline),
              const SizedBox(height: 10),
              _tf(_pEma, 'Correo', Icons.email_outlined),
              const SizedBox(height: 10),
              _tf(_pTel, 'Teléfono', Icons.phone_outlined),
              const SizedBox(height: 10),
              _tf(_pDir, 'Dirección', Icons.home_outlined),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: () async {
                    final err = await app.actualizarPerfil(
                      nombre: _pNom.text.trim(),
                      email: _pEma.text.trim(),
                      tel: _pTel.text.trim(),
                      dir: _pDir.text.trim(),
                    );
                    if (!context.mounted) return;
                    if (err != null) {
                      _snack(context, err);
                    } else {
                      _snack(context, 'Perfil actualizado');
                    }
                  },
                  child: const Text('Guardar cambios',
                      style: TextStyle(fontSize: 15, color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Cerrar sesión',
                  style: TextStyle(fontSize: 15, color: Colors.red,
                      fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                await app.logout();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false);
              },
            ),
          ),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  Widget _statChip(IconData icon, String val, String lbl) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      Icon(icon, size: 14, color: kPrimary),
      const SizedBox(width: 4),
      Text('$val $lbl',
          style: const TextStyle(fontSize: 11, color: kPrimary,
              fontWeight: FontWeight.w600)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════
//  PASOS
// ════════════════════════════════════════════════════════════════

class PasosScreen extends StatefulWidget {
  final AppProvider app;
  const PasosScreen({super.key, required this.app});
  @override State<PasosScreen> createState() => _PasosScreenState();
}

class _PasosScreenState extends State<PasosScreen>
    with SingleTickerProviderStateMixin {
  static const _kWalkHist = 'vet_walk_hist_v1';

  StreamSubscription<StepCount>? _sub;
  int _base = 0, _sesion = 0;
  bool _on = false, _err = false;
  int? _mid;
  final List<String> _hist = [];
  late AnimationController _ac;
  late Animation<double> _an;

  Future<void> _cargarHist() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_kWalkHist);
    if (!mounted || raw == null) return;
    setState(() {
      _hist
        ..clear()
        ..addAll(raw);
    });
  }

  Future<void> _persistHist() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kWalkHist, List<String>.from(_hist));
  }

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this,
        duration: const Duration(seconds: 2))..repeat(reverse: true);
    _an = Tween<double>(begin: -8, end: 8).animate(
        CurvedAnimation(parent: _ac, curve: Curves.easeInOut));
    _cargarHist();
  }

  void _iniciar() {
    setState(() { _on = true; _sesion = 0; _base = 0; });
    _sub = Pedometer.stepCountStream.listen(
      (e) => setState(() {
        if (_base == 0) _base = e.steps;
        _sesion = (e.steps - _base).clamp(0, 999999);
      }),
      onError: (_) { setState(() => _err = true); _simular(); },
      cancelOnError: true,
    );
  }

  void _simular() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 850));
      if (!_on || !mounted) return false;
      setState(() => _sesion++);
      return true;
    });
  }

  Future<void> _detener() async {
    _sub?.cancel();
    _sub = null;
    if (_mid == null) {
      _snack(context, 'Selecciona una mascota primero');
      return;
    }
    final nom = widget.app.mascotas
        .firstWhere((m) => m.id == _mid).nombre;
    final hoy = DateTime.now();
    setState(() {
      _hist.insert(0,
          '$nom  -  $_sesion pasos  -  ${hoy.day}/${hoy.month}/${hoy.year}');
      _on = false;
      _base = 0;
      _sesion = 0;
    });
    await _persistHist();
    if (context.mounted) {
      _snack(context, 'Caminata guardada');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: const Text('Registro de Caminata'),
          backgroundColor: kPrimary, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          AnimatedBuilder(
            animation: _an,
            builder: (_, __) => Transform.translate(
              offset: Offset(0, _an.value),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.pets, size: 60, color: kPrimary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('$_sesion', style: const TextStyle(fontSize: 72,
              fontWeight: FontWeight.bold, color: kPrimary)),
          const Text('pasos', style: TextStyle(color: Colors.grey, fontSize: 16)),
          if (_err)
            const Text('Modo simulación activo',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 20),
          Container(
            decoration: _cardDeco(),
            child: DropdownButtonFormField<int>(
              value: _mid,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Seleccionar mascota',
                prefixIcon: const Icon(Icons.pets, color: kPrimary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                filled: true, fillColor: Colors.white,
              ),
              items: app.mascotas.map((m) =>
                  DropdownMenuItem(value: m.id,
                      child: Text(m.nombre))).toList(),
              onChanged: (v) => setState(() => _mid = v),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow, color: Colors.white),
              label: const Text('Iniciar',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _on ? null : _iniciar,
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton.icon(
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text('Detener',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _on ? _detener : null,
            )),
          ]),
          const SizedBox(height: 20),
          const Align(alignment: Alignment.centerLeft,
              child: Text('Historial de caminatas',
                  style: TextStyle(fontWeight: FontWeight.bold,
                      fontSize: 15, color: Colors.black87))),
          const SizedBox(height: 10),
          Expanded(
            child: _hist.isEmpty
                ? Center(child: Text('Sin caminatas registradas',
                    style: TextStyle(color: Colors.grey.shade400)))
                : ListView.builder(
                    itemCount: _hist.length,
                    itemBuilder: (_, i) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: _cardDeco(),
                      child: Row(children: [
                        const Icon(Icons.directions_walk,
                            color: kPrimary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_hist[i],
                            style: const TextStyle(fontSize: 13))),
                      ]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  EXPEDIENTE
// ════════════════════════════════════════════════════════════════

class ExpedienteScreen extends StatefulWidget {
  final AppProvider app;
  const ExpedienteScreen({super.key, required this.app});
  @override State<ExpedienteScreen> createState() => _ExpedienteScreenState();
}

class _ExpedienteScreenState extends State<ExpedienteScreen> {
  bool _generando = false;

  Future<void> _generarPDF() async {
    setState(() => _generando = true);
    try {
      final app   = widget.app;
      final u     = app.usuarioActual;
      final ahora = DateTime.now();

      // Cargar fuentes Roboto con soporte UTF-8
      final fontData     = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      final ttf          = pw.Font.ttf(fontData);
      final ttfBold      = pw.Font.ttf(fontBoldData);

      final pdf = pw.Document();

      // Tema global con Roboto
      final theme = pw.ThemeData.withFont(
        base: ttf,
        bold: ttfBold,
      );

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: theme,  // ← aquí aplica la fuente
        header: (_) => pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFF1565C0),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
            pw.Text('EXPEDIENTE CLÍNICO',
                style: pw.TextStyle(fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white)),
            pw.Text(
                'Generado: ${ahora.day}/${ahora.month}/${ahora.year}',
                style: pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey300)),
          ]),
        ),
        build: (_) => [
          pw.SizedBox(height: 16),
          _exSec('DATOS DEL CLIENTE'),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(8))),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              _exFila('Nombre',   u?.nombre    ?? '-'),
              _exFila('Usuario',  u?.username  ?? '-'),
              _exFila('Correo',   u?.email     ?? '-'),
              _exFila('Teléfono', u?.telefono  ?? '-'),
              _exFila('Dirección',u?.direccion ?? '-'),
            ]),
          ),
          pw.SizedBox(height: 20),
          _exSec('CITAS'),
          pw.SizedBox(height: 8),
          app.citas.isEmpty
              ? _exVacio('Sin citas')
              : pw.Column(children: app.citas.map((c) {
                  final mNom = app.mascotas
                      .where((m) => m.id == c.mascotaId)
                      .map((m) => m.nombre)
                      .firstOrNull ?? '-';
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 6),
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(6))),
                    child: pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment.spaceBetween,
                        children: [
                      pw.Text(mNom,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 12)),
                      pw.Text(
                        '${c.fecha.day}/${c.fecha.month}/${c.fecha.year}  '
                        '${c.fecha.hour.toString().padLeft(2,'0')}:'
                        '${c.fecha.minute.toString().padLeft(2,'0')}  '
                        '${c.estadoDisplay}',
                        style: pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                    ]),
                  );
                }).toList()),
          pw.SizedBox(height: 20),
          ...app.mascotas.map((m) {
            final visitas = app.visitasDeMascota(m.id);
            return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              _exSec('MASCOTA: ${m.nombre.toUpperCase()}'),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8))),
                child: pw.Wrap(spacing: 20, runSpacing: 4, children: [
                  _exChip('Especie: ${m.especieDisplay}'),
                  _exChip('Raza: ${m.raza}'),
                  _exChip('Edad: ${m.edad} años'),
                  _exChip('Peso: ${m.peso} kg'),
                  _exChip('Color: ${m.color}'),
                ]),
              ),
              pw.SizedBox(height: 10),
              pw.Text('Historial de visitas',
                  style: pw.TextStyle(fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: const PdfColor.fromInt(0xFF1565C0))),
              pw.SizedBox(height: 4),
              visitas.isEmpty
                  ? _exVacio('Sin visitas')
                  : pw.Column(children: visitas.map((v) => pw.Container(
                        margin: const pw.EdgeInsets.only(bottom: 5),
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.blue200),
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(6))),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                          pw.Text(v.diagnostico,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11)),
                          pw.Text('Tratamiento: ${v.tratamiento}',
                              style: pw.TextStyle(
                                  fontSize: 10, color: PdfColors.grey700)),
                        ]),
                      )).toList()),
              pw.SizedBox(height: 20),
            ]);
          }),
        ],
      ));

      // Reemplaza la parte final del método:
      final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final path = '${dir.path}/expediente_${ahora.millisecondsSinceEpoch}.pdf';
      final file = File(path);
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      setState(() => _generando = false);

      // Abrir el PDF directamente
      await OpenFile.open(path);
      _snack(context, 'PDF guardado en: $path');
    } catch (e) {
      if (!mounted) return;
      setState(() => _generando = false);
      _snack(context, 'Error al generar PDF: $e');
    }
  }

  pw.Widget _exSec(String t) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFF1565C0),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(6))),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 11,
            fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      );

  pw.Widget _exFila(String lbl, String val) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(width: 130,
              child: pw.Text(lbl, style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 11, color: PdfColors.grey700))),
          pw.Text(val, style: pw.TextStyle(fontSize: 11)),
        ]),
      );

  pw.Widget _exChip(String txt) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: pw.BoxDecoration(color: PdfColors.white,
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(10)),
            border: pw.Border.all(color: PdfColors.blue200)),
        child: pw.Text(txt,
            style: pw.TextStyle(fontSize: 9, color: PdfColors.blue900)),
      );

  pw.Widget _exVacio(String msg) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(msg,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey400)),
      );

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final u   = app.usuarioActual;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Expediente Clínico'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
        actions: [
          if (_generando)
            const Padding(padding: EdgeInsets.all(16),
                child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)))
          else
            IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _generarPDF),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download, color: Colors.white),
              label: Text(_generando ? 'Generando...' : 'Descargar PDF',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16))),
              onPressed: _generando ? null : _generarPDF,
            ),
          ),
          const SizedBox(height: 24),

          // Cliente
          _secCard(title: 'Cliente', icon: Icons.person_outline,
              color: kPrimary,
              child: Column(children: [
                _infoRow(Icons.person, u?.nombre ?? '-'),
                _infoRow(Icons.alternate_email, u?.username ?? '-'),
                _infoRow(Icons.email, u?.email ?? '-'),
                _infoRow(Icons.phone, u?.telefono ?? '-'),
              ])),
          const SizedBox(height: 16),

          // Citas
          _secCard(
            title: 'Citas (${app.citas.length})',
            icon: Icons.calendar_today, color: Colors.indigo,
            child: app.citas.isEmpty
                ? _empty('Sin citas registradas')
                : Column(children: app.citas.map((c) {
                    final mNom = app.mascotas
                        .where((m) => m.id == c.mascotaId)
                        .map((m) => m.nombre)
                        .firstOrNull ?? '-';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: kBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200)),
                      child: Row(children: [
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(mNom, style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            '${c.fecha.day}/${c.fecha.month}/${c.fecha.year}  '
                            '${c.fecha.hour.toString().padLeft(2,'0')}:'
                            '${c.fecha.minute.toString().padLeft(2,'0')}',
                            style: TextStyle(fontSize: 11,
                                color: Colors.grey.shade500),
                          ),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: c.estado == 'cancelled'
                                  ? Colors.red.shade50
                                  : Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(c.estadoDisplay,
                              style: TextStyle(fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: c.estado == 'cancelled'
                                      ? Colors.red.shade700
                                      : Colors.green.shade700)),
                        ),
                      ]),
                    );
                  }).toList()),
          ),
          const SizedBox(height: 16),

          // Mascotas
          ...app.mascotas.map((m) {
            final visitas = app.visitasDeMascota(m.id);
            return Column(children: [
              _secCard(title: m.nombre, icon: Icons.pets,
                  color: Colors.teal,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _chip(m.especieDisplay),
                      _chip(m.raza),
                      _chip('${m.edad} años'),
                      _chip('${m.peso} kg'),
                      _chip(m.color),
                    ]),
                    const SizedBox(height: 12),
                    const Divider(),
                    const Text('Historial de visitas',
                        style: TextStyle(fontWeight: FontWeight.bold,
                            fontSize: 13)),
                    const SizedBox(height: 8),
                    visitas.isEmpty
                        ? _empty('Sin visitas')
                        : Column(children: visitas.map((v) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2FD),
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                Text(v.diagnostico,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                Text(v.tratamiento,
                                    style: TextStyle(fontSize: 11,
                                        color: Colors.grey.shade600)),
                              ]),
                            )).toList()),
                  ])),
              const SizedBox(height: 16),
            ]);
          }),
          const SizedBox(height: 30),
        ]),
      ),
    );
  }

  

  Widget _secCard({required String title, required IconData icon,
      required Color color, required Widget child}) =>
      Container(
        decoration: _cardDeco(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 15, color: color)),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );

  Widget _infoRow(IconData icon, String txt) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(child: Text(txt,
              style: const TextStyle(fontSize: 13))),
        ]),
      );

  Widget _chip(String txt) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.teal.withOpacity(0.3))),
        child: Text(txt,
            style: const TextStyle(fontSize: 11, color: Colors.teal)),
      );

  Widget _empty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(msg,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      );
}

class CitaDetalleScreen extends StatelessWidget {
  final int citaId;
  const CitaDetalleScreen({super.key, required this.citaId});

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context, listen: false);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Detalle de Cita'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: FutureBuilder<CitaCompleta?>(
        future: app.getCitaDetalle(citaId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final cita = snap.data;
          if (cita == null) {
            return const Center(child: Text('No se pudo cargar la cita'));
          }
          final mascota = app.mascotas.where((m) => m.id == cita.mascotaId).firstOrNull;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [

              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPrimary, kAccent]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.event, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${cita.fecha.day}/${cita.fecha.month}/${cita.fecha.year}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${cita.fecha.hour.toString().padLeft(2,'0')}:${cita.fecha.minute.toString().padLeft(2,'0')}',
                        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                      ),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(cita.estadoDisplay,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),

              // Info general
              Container(
                decoration: _cardDeco(),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Información', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kPrimary)),
                  const Divider(),
                  if (mascota != null) _infoRow(Icons.pets, 'Mascota', mascota.nombre),
                  if (cita.servicioNombre != null) _infoRow(Icons.medical_services, 'Servicio', cita.servicioNombre!),
                  if (cita.veterinarioNombre != null) _infoRow(Icons.person_outline, 'Veterinario', 'Dr(a). ${cita.veterinarioNombre!}'),
                  if (cita.notas.isNotEmpty) _infoRow(Icons.notes, 'Notas', cita.notas),
                ]),
              ),
              const SizedBox(height: 16),

              // Consulta
              if (cita.consulta != null) ...[
                Container(
                  decoration: _cardDeco(),
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Consulta Médica', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kPrimary)),
                    const Divider(),
                    _infoRow(Icons.help_outline, 'Motivo', cita.consulta!.motivo),
                    _infoRow(Icons.search, 'Diagnóstico', cita.consulta!.diagnostico),
                    _infoRow(Icons.healing, 'Tratamiento', cita.consulta!.tratamiento),
                    if (cita.consulta!.peso != null) _infoRow(Icons.monitor_weight, 'Peso', '${cita.consulta!.peso} kg'),
                    if (cita.consulta!.temperatura != null) _infoRow(Icons.thermostat, 'Temperatura', '${cita.consulta!.temperatura}°C'),
                    if (cita.consulta!.proximaVisita != null) _infoRow(Icons.calendar_today, 'Próxima visita', cita.consulta!.proximaVisita!),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              // Receta
              if (cita.consulta?.receta != null) ...[
                Container(
                  decoration: _cardDeco(),
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Receta Médica', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                    const Divider(),
                    if (cita.consulta!.receta!.instrucciones.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(cita.consulta!.receta!.instrucciones,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      ),
                    ...cita.consulta!.receta!.medicamentos.map((m) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.medicamento, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('${m.dosis} — ${m.frecuencia} — ${m.duracion}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        if (m.instrucciones != null)
                          Text(m.instrucciones!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                    )),
                  ]),
                ),
              ],

            ]),
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: kPrimary),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );
}

class ServiciosScreen extends StatelessWidget {
  final int? preseleccionarServicioId;
  const ServiciosScreen({super.key, this.preseleccionarServicioId});

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Servicios'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: app.servicios.isEmpty
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: app.servicios.length,
              itemBuilder: (_, i) {
                final s = app.servicios[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: _cardDeco(),
                  child: Column(children: [
                    // Header servicio
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kPrimary, kLight]),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.medical_services, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('\$${s.precio.toStringAsFixed(0)} · ${s.duracion} min',
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                        ])),
                        ElevatedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ReservarCitaScreen(servicioPreseleccionado: s),
                          )),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: kPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('Reservar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    ),
                    // Descripción
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (s.descripcion.isNotEmpty)
                          Text(s.descripcion, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        if (s.veterinarios.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Veterinarios disponibles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          ...s.veterinarios.map((v) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFE3F2FD),
                              backgroundImage: v.foto != null && v.foto!.isNotEmpty
                                  ? NetworkImage(_fotoAbsoluta(v.foto!)) : null,
                              child: v.foto == null || v.foto!.isEmpty
                                  ? const Icon(Icons.person, color: kPrimary, size: 20) : null,
                            ),
                            title: Text('Dr(a). ${v.nombre}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(v.especialidad, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          )),
                        ],
                      ]),
                    ),
                  ]),
                );
              },
            ),
    );
  }

  String _fotoAbsoluta(String foto) {
    if (foto.startsWith('http')) return foto;
    return '${ApiService.serverOrigin}$foto';
  }
}

class VeterinariosScreen extends StatelessWidget {
  const VeterinariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Veterinarios'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: app.veterinarios.isEmpty
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: app.veterinarios.length,
              itemBuilder: (_, i) {
                final v = app.veterinarios[i];
                final fotoUrl = v.foto != null && v.foto!.isNotEmpty
                    ? (v.foto!.startsWith('http') ? v.foto! : '${ApiService.serverOrigin}${v.foto}')
                    : null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: _cardDeco(),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [kPrimary, kLight]),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white.withOpacity(0.2),
                          backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
                          child: fotoUrl == null ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Dr(a). ${v.nombre}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(v.especialidad,
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
                        ])),
                        ElevatedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ReservarCitaScreen(veterinarioPreseleccionado: v),
                          )),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: kPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('Reservar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Servicios del vet
                        ...app.servicios
                            .where((s) => s.veterinarios.any((sv) => sv.id == v.id))
                            .map((s) => Chip(
                              label: Text(s.nombre, style: const TextStyle(fontSize: 11)),
                              backgroundColor: const Color(0xFFE3F2FD),
                              side: BorderSide.none,
                            )),
                      ]),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class ReservarCitaScreen extends StatefulWidget {
  final Servicio? servicioPreseleccionado;
  final Veterinario? veterinarioPreseleccionado;
  const ReservarCitaScreen({super.key, this.servicioPreseleccionado, this.veterinarioPreseleccionado});

  @override
  State<ReservarCitaScreen> createState() => _ReservarCitaScreenState();
}

class _ReservarCitaScreenState extends State<ReservarCitaScreen> {
  int? _mascotaId, _servicioId, _veterinarioId;
  DateTime _fecha = DateTime.now();
  String _hora = '';
  String _notas = '';
  List<Veterinario> _vetsDisponibles = [];
  List<String> _slots = [];

  static const _horariosDefault = [
    '09:00','09:30','10:00','10:30','11:00','11:30',
    '15:00','15:30','16:00','16:30',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.servicioPreseleccionado != null) {
      _servicioId = widget.servicioPreseleccionado!.id;
      _vetsDisponibles = widget.servicioPreseleccionado!.veterinarios;
    }
    if (widget.veterinarioPreseleccionado != null) {
      _veterinarioId = widget.veterinarioPreseleccionado!.id;
      _vetsDisponibles = [widget.veterinarioPreseleccionado!];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final app = Provider.of<AppProvider>(context, listen: false);
        final serviciosDelVet = app.servicios
            .where((s) => s.veterinarios.any((v) => v.id == _veterinarioId))
            .toList();
        if (serviciosDelVet.isNotEmpty) {
          setState(() {
            _servicioId = serviciosDelVet.first.id;
            _vetsDisponibles = serviciosDelVet.first.veterinarios;
          });
        }
        _cargarSlots();
      });
    }
  }

  void _onServicioChanged(int? id) {
    final app = Provider.of<AppProvider>(context, listen: false);
    final servicio = app.servicios.where((s) => s.id == id).firstOrNull;
    setState(() {
      _servicioId = id;
      _veterinarioId = null;
      _vetsDisponibles = servicio?.veterinarios ?? [];
      _hora = '';
      _slots = [];
    });
  }

  Future<void> _cargarSlots() async {
    if (_veterinarioId == null) return;
    try {
      final dateStr = '${_fecha.year}-${_fecha.month.toString().padLeft(2,'0')}-${_fecha.day.toString().padLeft(2,'0')}';
      final slots = await ApiService.getAvailableSlots(_veterinarioId!, dateStr);
      if (!mounted) return;
      setState(() { _slots = slots; _hora = ''; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _slots = _horariosDefault; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Reservar Cita'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Mascota
          Container(
            decoration: _cardDeco(),
            child: DropdownButtonFormField<int>(
              value: _mascotaId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Mascota *',
                prefixIcon: Icon(Icons.pets, color: kPrimary),
                border: OutlineInputBorder(borderSide: BorderSide.none),
                filled: true, fillColor: Colors.white,
              ),
              items: app.mascotas.map((m) => DropdownMenuItem(
                value: m.id, child: Text('${m.nombre} (${m.especieDisplay})'),
              )).toList(),
              onChanged: (v) => setState(() => _mascotaId = v),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 12),

          // Servicio
          Container(
            decoration: _cardDeco(),
            child: DropdownButtonFormField<int>(
              value: _servicioId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Servicio *',
                prefixIcon: Icon(Icons.medical_services, color: kPrimary),
                border: OutlineInputBorder(borderSide: BorderSide.none),
                filled: true, fillColor: Colors.white,
              ),
              items: app.servicios.map((s) => DropdownMenuItem(
                value: s.id,
                child: Text('${s.nombre} — \$${s.precio.toStringAsFixed(0)}'),
              )).toList(),
              onChanged: _onServicioChanged,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 12),

          // Veterinario
          if (_vetsDisponibles.isNotEmpty) ...[
            Container(
              decoration: _cardDeco(),
              child: DropdownButtonFormField<int>(
                value: _veterinarioId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Veterinario (opcional)',
                  prefixIcon: Icon(Icons.person_outline, color: kPrimary),
                  border: OutlineInputBorder(borderSide: BorderSide.none),
                  filled: true, fillColor: Colors.white,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Sin preferencia')),
                  ..._vetsDisponibles.map((v) => DropdownMenuItem(
                    value: v.id, child: Text('Dr(a). ${v.nombre}'),
                  )),
                ],
                onChanged: (v) {
                  setState(() { _veterinarioId = v; _hora = ''; _slots = []; });
                  if (v != null) _cargarSlots();
                },
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Fecha
          const Text('Fecha', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          Container(
            decoration: _cardDeco(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CalendarDatePicker(
                initialDate: _fecha,
                firstDate: DateTime.now(),
                lastDate: DateTime(2030),
                onDateChanged: (d) {
                  setState(() { _fecha = d; _hora = ''; _slots = []; });
                  if (_veterinarioId != null) _cargarSlots();
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Horarios
          const Text('Horario', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (_slots.isNotEmpty ? _slots : _horariosDefault).length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, crossAxisSpacing: 8,
              mainAxisSpacing: 8, childAspectRatio: 2.2,
            ),
            itemBuilder: (_, i) {
              final hora = (_slots.isNotEmpty ? _slots : _horariosDefault)[i];
              final sel = hora == _hora;
              return GestureDetector(
                onTap: () => setState(() => _hora = hora),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? kPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? kPrimary : Colors.grey.shade200),
                  ),
                  child: Text(hora, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.black87,
                  )),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Notas
          TextField(
            decoration: InputDecoration(
              labelText: 'Notas (opcional)',
              prefixIcon: const Icon(Icons.notes, color: kPrimary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onChanged: (v) => _notas = v,
          ),
          const SizedBox(height: 24),

          // Botón confirmar
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (_mascotaId != null && _servicioId != null && _hora.isNotEmpty)
                    ? kPrimary : Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: (_mascotaId == null || _servicioId == null || _hora.isEmpty)
                  ? null
                  : () async {
                      final pp = _hora.split(':');
                      final hh = int.tryParse(pp[0]) ?? 0;
                      final mm = int.tryParse(pp[1]) ?? 0;
                      final fc = DateTime(_fecha.year, _fecha.month, _fecha.day, hh, mm);
                      final err = await app.agregarCita(Cita(
                        id: 0, mascotaId: _mascotaId!, fecha: fc,
                        veterinarioId: _veterinarioId,
                        servicioId: _servicioId,
                        notas: _notas,
                      ));
                      if (!context.mounted) return;
                      if (err != null) {
                        _snack(context, err);
                      } else {
                        _snack(context, 'Cita agendada correctamente');
                        Navigator.pop(context);
                      }
                    },
              child: Text('Confirmar Cita',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,
                  color: (_mascotaId != null && _servicioId != null && _hora.isNotEmpty)
                      ? Colors.white : Colors.grey.shade500,
                )),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class HistorialMedicoScreen extends StatelessWidget {
  final AppProvider app;
  const HistorialMedicoScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Historial Médico'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: Column(children: [
        if (app.hospitalizaciones.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => HospitalizacionesScreen(app: app),
              )),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.local_hospital, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Hospitalizaciones (${app.hospitalizaciones.length})',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    Text('Ver historial de hospitalizaciones',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
                  ])),
                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.red.shade400),
                ]),
              ),
            ),
          ),
        Expanded(
          child: app.historialMedico.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Sin historial médico',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text('Las citas completadas aparecerán aquí',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                ]))
              : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: app.historialMedico.length,
              itemBuilder: (_, i) {
                final cita = app.historialMedico[i];
                final mascota = app.mascotas.where((m) => m.id == cita.mascotaId).firstOrNull;
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => CitaDetalleScreen(citaId: cita.id),
                  )),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: _cardDeco(),
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(mascota?.nombre ?? 'Mascota',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (cita.servicioNombre != null)
                          Text(cita.servicioNombre!,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        Text(
                          '${cita.fecha.day}/${cita.fecha.month}/${cita.fecha.year}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        if (cita.consulta != null)
                          Text(cita.consulta!.diagnostico,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      ])),
                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey.shade400),
                    ]),
                  ),
                );
              },
            ),
        ),
      ]),
    );
  }
}

class MascotaDetalleScreen extends StatelessWidget {
  final Mascota mascota;
  const MascotaDetalleScreen({super.key, required this.mascota});

  @override
  Widget build(BuildContext context) {
    final app = Provider.of<AppProvider>(context, listen: false);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(mascota.nombre),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _dlgEditarMascotaExterno(context, app, mascota),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // Avatar grande
          Center(child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kPrimary, width: 3),
            ),
            child: ClipOval(child: mascota.fotoUrlAbsoluta != null
                ? Image.network(mascota.fotoUrlAbsoluta!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 60, color: kPrimary))
                : const Icon(Icons.pets, size: 60, color: kPrimary)),
          )),
          const SizedBox(height: 12),
          Text(mascota.nombre, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(mascota.especieDisplay, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 24),

          // Info
          Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Información', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kPrimary)),
              const Divider(),
              _row('Raza', mascota.raza.isNotEmpty ? mascota.raza : 'No especificada'),
              _row('Edad', '${mascota.edad} años'),
              _row('Peso', '${mascota.peso} kg'),
              _row('Color', mascota.color.isNotEmpty ? mascota.color : 'No especificado'),
              _row('Vacunación', mascota.estadoVacunacionDisplay),
            ]),
          ),
          const SizedBox(height: 16),

          // Vacunas
          if (mascota.notasVacunas.isNotEmpty) Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Vacunas y Tratamientos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
              const Divider(),
              Text(mascota.notasVacunas, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ]),
          ),
          const SizedBox(height: 16),

          // Botón reservar cita
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month, color: Colors.white),
              label: const Text('Reservar Cita', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ReservarCitaScreen(),
              )),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      SizedBox(width: 100, child: Text(label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );

  void _dlgEditarMascotaExterno(BuildContext context, AppProvider app, Mascota m) {
    // Reutiliza el diálogo de edición existente
    final state = context.findAncestorStateOfType<_HomeScreenState>();
    state?._dlgEditarMascota(app, m);
  }
}

// ════════════════════════════════════════════════════════════════
//  HELPERS GLOBALES
// ════════════════════════════════════════════════════════════════

BoxDecoration _cardDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ],
    );

Widget _tf(TextEditingController ctrl, String label, IconData icon,
    {bool obs = false}) =>
    TextField(
      controller: ctrl, obscureText: obs,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimary, width: 2)),
      ),
    );

Widget _tfObs(TextEditingController ctrl, String label,
    bool obs, VoidCallback toggle) =>
    TextField(
      controller: ctrl, obscureText: obs,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, color: kPrimary),
        suffixIcon: IconButton(
            icon: Icon(obs ? Icons.visibility_off : Icons.visibility),
            onPressed: toggle),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimary, width: 2)),
      ),
    );

Widget _priBtn(String label, VoidCallback fn) => SizedBox(
      width: double.infinity, height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14))),
        onPressed: fn,
        child: Text(label, style: const TextStyle(fontSize: 16,
            color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );

void _snack(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

// ════════════════════════════════════════════════════════════════
//  MAIN
// ════════════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(
    create: (_) => AppProvider(),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clínica Veterinaria',
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: kPrimary,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kPrimary,
          brightness: Brightness.light,
          primary: kPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimary, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const SplashScreen(),
    ),
  ));
}

// ════════════════════════════════════════════════════════════════
//  HOSPITALIZACIONES
// ════════════════════════════════════════════════════════════════

class HospitalizacionesScreen extends StatelessWidget {
  final AppProvider app;
  const HospitalizacionesScreen({super.key, required this.app});

  Color _colorEstado(String status) {
    switch (status) {
      case 'active': return Colors.red;
      case 'discharged': return Colors.green;
      case 'transferred': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Color _colorPaciente(String status) {
    switch (status) {
      case 'critical': return Colors.red;
      case 'serious': return Colors.orange;
      case 'stable': return Colors.blue;
      case 'improving': return Colors.lightBlue;
      default: return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Hospitalizaciones'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: app.hospitalizaciones.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.local_hospital_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text('Sin hospitalizaciones',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 6),
              Text('Las hospitalizaciones de tus mascotas aparecerán aquí',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  textAlign: TextAlign.center),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: app.hospitalizaciones.length,
              itemBuilder: (_, i) {
                final h = app.hospitalizaciones[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => HospitalizacionDetalleScreen(hospitalizacionId: h.id),
                  )),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border(left: BorderSide(color: _colorEstado(h.status), width: 4)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0xFFBBDEFB),
                            ),
                            child: h.petPhoto != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(h.petPhoto!, fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.pets, color: kPrimary)))
                                : const Icon(Icons.pets, color: kPrimary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h.petName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _colorEstado(h.status).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(h.statusDisplay,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                        color: _colorEstado(h.status))),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _colorPaciente(h.patientStatus).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(h.patientStatusDisplay,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                        color: _colorPaciente(h.patientStatus))),
                              ),
                            ]),
                          ])),
                          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                        ]),
                        const SizedBox(height: 12),
                        Text('Dx: ${h.initialDiagnosis}',
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text('Ingreso: ${h.admissionDate.substring(0, 10)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          if (h.veterinarianName != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.person_outline, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Expanded(child: Text('Dr(a). ${h.veterinarianName!}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500))),
                          ],
                        ]),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class HospitalizacionDetalleScreen extends StatefulWidget {
  final int hospitalizacionId;
  const HospitalizacionDetalleScreen({super.key, required this.hospitalizacionId});
  @override State<HospitalizacionDetalleScreen> createState() => _HospitalizacionDetalleScreenState();
}

class _HospitalizacionDetalleScreenState extends State<HospitalizacionDetalleScreen> {
  Hospitalizacion? _hosp;
  bool _loading = true;

  @override
  void initState() { super.initState(); _cargar(); }

  Future<void> _cargar() async {
    try {
      final data = await ApiService.getHospitalizacionDetalle(widget.hospitalizacionId);
      setState(() { _hosp = Hospitalizacion.fromJson(data); _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(_hosp?.petName ?? 'Hospitalización'),
        backgroundColor: kPrimary, foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _hosp == null
              ? const Center(child: Text('No se pudo cargar'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [

                    // Info general
                    _secCard('Información General', Icons.info_outline, kPrimary,
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _fila('Mascota', _hosp!.petName),
                        if (_hosp!.veterinarianName != null)
                          _fila('Veterinario', 'Dr(a). ${_hosp!.veterinarianName!}'),
                        _fila('Ingreso', _hosp!.admissionDate.substring(0, 16).replaceAll('T', ' ')),
                        if (_hosp!.dischargeDate != null)
                          _fila('Alta', _hosp!.dischargeDate!.substring(0, 16).replaceAll('T', ' ')),
                        _fila('Motivo', _hosp!.reason),
                        _fila('Diagnóstico inicial', _hosp!.initialDiagnosis),
                        if (_hosp!.notes != null && _hosp!.notes!.isNotEmpty)
                          _fila('Notas', _hosp!.notes!),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Monitoreo
                    if (_hosp!.monitoring.isNotEmpty) ...[
                      _secCard('Monitoreo', Icons.monitor_heart, Colors.red,
                        Column(children: _hosp!.monitoring.map((rec) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kBg, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(rec['recorded_at']?.toString().substring(0, 16).replaceAll('T', ' ') ?? '',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 12, runSpacing: 8, children: [
                              if (rec['temperature'] != null) _vital('${rec['temperature']}°C', 'Temp'),
                              if (rec['heart_rate'] != null) _vital('${rec['heart_rate']}', 'FC'),
                              if (rec['respiratory_rate'] != null) _vital('${rec['respiratory_rate']}', 'FR'),
                              if (rec['weight'] != null) _vital('${rec['weight']} kg', 'Peso'),
                            ]),
                            if (rec['observations'] != null && rec['observations'].toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(rec['observations'], style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                            ],
                          ]),
                        )).toList()),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Tratamientos
                    if (_hosp!.treatments.isNotEmpty) ...[
                      _secCard('Tratamientos', Icons.medication, Colors.purple,
                        Column(children: _hosp!.treatments.map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t['medication'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('${t['dose']} · ${t['frequency']} · ${t['route']}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ])),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: t['status'] == 'active' ? Colors.green.shade50 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(t['status_display'] ?? '',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                      color: t['status'] == 'active' ? Colors.green.shade700 : Colors.grey.shade600)),
                            ),
                          ]),
                        )).toList()),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Orden médica
                    if (_hosp!.order != null) ...[
                      _secCard('Orden Médica', Icons.assignment, Colors.teal,
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _fila('Dieta', _hosp!.order!['diet'] ?? ''),
                          if (_hosp!.order!['fluid_therapy'] == true)
                            _fila('Fluidoterapia', _hosp!.order!['fluid_therapy_detail'] ?? 'Activa'),
                          if (_hosp!.order!['laboratory'] == true)
                            _fila('Laboratorio', _hosp!.order!['laboratory_detail'] ?? 'Indicado'),
                          if (_hosp!.order!['xray'] == true)
                            _fila('Rayos X', _hosp!.order!['xray_detail'] ?? 'Indicado'),
                          if (_hosp!.order!['ultrasound'] == true)
                            _fila('Ultrasonido', _hosp!.order!['ultrasound_detail'] ?? 'Indicado'),
                          if (_hosp!.order!['special_instructions'] != null &&
                              _hosp!.order!['special_instructions'].toString().isNotEmpty)
                            _fila('Indicaciones', _hosp!.order!['special_instructions']),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 30),
                  ]),
                ),
    );
  }

  Widget _secCard(String title, IconData icon, Color color, Widget child) =>
      Container(
        width: double.infinity,
        decoration: _cardDeco(),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _fila(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _vital(String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200)),
    child: Column(children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ]),
  );
}