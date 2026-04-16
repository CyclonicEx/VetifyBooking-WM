from django.shortcuts import get_object_or_404
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.http import HttpResponse
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.authentication import TokenAuthentication
from rest_framework.response import Response
from rest_framework.authtoken.models import Token
import json

from booking.models import (
    Appointment, Pet, Service, Veterinarian,
    ClinicSchedule, UserProfile, MedicalConsultation,
    MedicalPrescription, PrescriptionItem, Vaccine,
)
from .serializers import (
    AppointmentSerializer, PetSerializer, ServiceSerializer,
    VeterinarianSerializer, ClinicScheduleSerializer,
    UserProfileSerializer, MedicalConsultationSerializer,
    MedicalPrescriptionSerializer, PrescriptionItemSerializer,
    VacunaSerializer,
)


# ── AUTH ─────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([AllowAny])
def api_login(request):
    password = request.data.get('password')
    email = (request.data.get('email') or '').strip()
    username = (request.data.get('username') or '').strip()

    if not password:
        return Response({'detail': 'La contraseña es obligatoria.'},
                        status=status.HTTP_400_BAD_REQUEST)

    user = None
    if email:
        cuenta = User.objects.filter(email__iexact=email).first()
        if cuenta:
            user = authenticate(request, username=cuenta.username, password=password)
    elif username:
        user = authenticate(request, username=username, password=password)
    else:
        return Response({'detail': 'Indica tu correo y contraseña.'},
                        status=status.HTTP_400_BAD_REQUEST)

    if user is None:
        return Response({'detail': 'Correo o contraseña incorrectos.'},
                        status=status.HTTP_400_BAD_REQUEST)

    token, _ = Token.objects.get_or_create(user=user)
    return Response({'token': token.key, 'user_id': user.pk})


@api_view(['POST'])
@permission_classes([AllowAny])
def api_register(request):
    username = (request.data.get('username') or '').strip()
    email = (request.data.get('email') or '').strip()
    password = request.data.get('password') or ''
    password2 = (request.data.get('password_confirm') or
                 request.data.get('password2') or '')
    phone = (request.data.get('phone') or '').strip()
    first_name = (request.data.get('first_name') or '').strip()

    errors = {}
    if not username:
        errors['username'] = ['Este campo es obligatorio.']
    if not email:
        errors['email'] = ['Este campo es obligatorio.']
    if not password:
        errors['password'] = ['Este campo es obligatorio.']
    if password != password2:
        errors['password_confirm'] = ['Las contraseñas no coinciden.']
    if len(password) < 8:
        errors['password'] = ['Mínimo 8 caracteres.']
    if User.objects.filter(username__iexact=username).exists():
        errors['username'] = ['Ese usuario ya existe.']
    if User.objects.filter(email__iexact=email).exists():
        errors['email'] = ['Ese correo ya está registrado.']
    if errors:
        return Response(errors, status=status.HTTP_400_BAD_REQUEST)

    user = User.objects.create_user(
        username=username, email=email,
        password=password, first_name=first_name or username,
    )
    if phone:
        profile, _ = UserProfile.objects.get_or_create(user=user)
        profile.phone = phone
        profile.save()

    token, _ = Token.objects.get_or_create(user=user)
    return Response({'token': token.key, 'user_id': user.pk},
                    status=status.HTTP_201_CREATED)


@api_view(['GET', 'PUT'])
@permission_classes([IsAuthenticated])
def mi_cuenta(request):
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    if request.method == 'GET':
        avatar_url = None
        if profile.avatar:
            avatar_url = request.build_absolute_uri(profile.avatar.url)
        return Response({
            'profile_id': profile.pk,
            'username': request.user.username,
            'first_name': request.user.first_name or '',
            'email': request.user.email or '',
            'phone': profile.phone or '',
            'address': profile.address or '',
            'avatar': avatar_url,
        })
    first_name = (request.data.get('first_name') or '').strip()
    email = (request.data.get('email') or '').strip()
    phone = request.data.get('phone')
    address = request.data.get('address')
    if email:
        request.user.email = email
    if first_name:
        request.user.first_name = first_name
    request.user.save()
    profile.phone = str(phone).strip() if phone else ''
    profile.address = str(address).strip() if address else ''
    profile.save()
    return Response({
        'profile_id': profile.pk,
        'username': request.user.username,
        'first_name': request.user.first_name,
        'email': request.user.email,
        'phone': profile.phone or '',
        'address': profile.address or '',
    })


# ── MASCOTAS ─────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def mascotas_lista(request):
    if request.method == 'GET':
        mascotas = Pet.objects.filter(owner=request.user)
        serializer = PetSerializer(mascotas, many=True)
        return Response(serializer.data)

    serializer = PetSerializer(data=request.data)
    if serializer.is_valid():
        serializer.save(owner=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET', 'PUT', 'PATCH', 'DELETE'])
@permission_classes([IsAuthenticated])
def mascota_detalle(request, pk):
    mascota = get_object_or_404(Pet, pk=pk, owner=request.user)

    if request.method == 'GET':
        return Response(PetSerializer(mascota).data)

    if request.method in ('PUT', 'PATCH'):
        serializer = PetSerializer(mascota, data=request.data,
                                   partial=request.method == 'PATCH')
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    mascota.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


# ── CITAS ─────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def citas_lista(request):
    if request.method == 'GET':
        citas = Appointment.objects.filter(user=request.user)
        return Response(AppointmentSerializer(citas, many=True).data)

    data = request.data
    fecha = data.get('date')
    hora  = data.get('time')
    vet   = data.get('veterinarian')

    # Validar cita duplicada del mismo usuario
    cita_duplicada = Appointment.objects.filter(
        user=request.user,
        pet_id=data.get('pet'),
        date=fecha,
        time=hora,
    ).exclude(status='cancelled').exists()

    if cita_duplicada:
        return Response(
            {'detail': 'Ya tienes una cita agendada en esa fecha y hora.'},
            status=status.HTTP_400_BAD_REQUEST
        )

    # Validar mismo veterinario misma fecha y hora
    if vet:
        vet_ocupado = Appointment.objects.filter(
            veterinarian_id=vet,
            date=fecha,
            time=hora,
        ).exclude(status='cancelled').exists()

        if vet_ocupado:
            return Response(
                {'detail': 'El veterinario ya tiene una cita en esa fecha y hora. Por favor elige otro horario.'},
                status=status.HTTP_400_BAD_REQUEST
            )

    serializer = AppointmentSerializer(data=data,
                                       context={'request': request})
    if serializer.is_valid():
        serializer.save(user=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['GET', 'PUT', 'DELETE'])
@permission_classes([IsAuthenticated])
def cita_detalle(request, pk):
    cita = get_object_or_404(Appointment, pk=pk, user=request.user)

    if request.method == 'GET':
        return Response(AppointmentSerializer(cita).data)

    if request.method == 'PUT':
        serializer = AppointmentSerializer(cita, data=request.data,
                                           context={'request': request})
        if serializer.is_valid():
            serializer.save()
            return Response(serializer.data)
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    cita.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


# ── SERVICIOS ─────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([AllowAny])
def servicios_lista(request):
    servicios = Service.objects.filter(is_active=True)
    return Response(ServiceSerializer(servicios, many=True).data)


# ── VETERINARIOS ─────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([AllowAny])
def veterinarios_lista(request):
    vets = Veterinarian.objects.filter(is_active=True)
    return Response(VeterinarianSerializer(vets, many=True).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def vets_por_servicio(request, service_id):
    vets = Veterinarian.objects.filter(
        services__id=service_id, is_active=True
    ).values('id', 'name', 'specialty')
    return Response({'vets': list(vets)})


# ── HORARIOS ─────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([AllowAny])
def horarios_lista(request):
    DAY_ORDER = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']
    horarios = list(ClinicSchedule.objects.all())
    horarios.sort(key=lambda s: DAY_ORDER.index(s.day_of_week) if s.day_of_week in DAY_ORDER else 99)
    
    data = []
    for h in horarios:
        data.append({
            'id': h.id,
            'day_of_week': h.day_of_week,
            'get_day_of_week_display': h.get_day_of_week_display(),
            'is_open': h.is_open,
            'opening_time': str(h.opening_time) if h.opening_time else None,
            'closing_time': str(h.closing_time) if h.closing_time else None,
            'notes': h.notes or '',
        })
    
    from django.http import JsonResponse
    import json
    return HttpResponse(
        json.dumps(data, ensure_ascii=False),
        content_type='application/json; charset=utf-8'
    )

# ── AVAILABLE SLOTS ──────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def available_slots(request):
    vet_id = request.query_params.get('vet_id')
    date = request.query_params.get('date')

    if not vet_id or not date:
        return Response({'error': 'vet_id y date son requeridos'},
                        status=status.HTTP_400_BAD_REQUEST)

    all_slots = [
        '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
        '15:00', '15:30', '16:00', '16:30',
    ]

    ocupados = Appointment.objects.filter(
        veterinarian_id=vet_id, date=date
    ).exclude(status='cancelled').values_list('time', flat=True)

    ocupados_str = [t.strftime('%H:%M') for t in ocupados]
    disponibles = [s for s in all_slots if s not in ocupados_str]

    return Response({'available_slots': disponibles})


# ── VACUNAS ───────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def vacunas_lista(request):
    if request.method == 'GET':
        pet_id = request.query_params.get('pet_id')
        if pet_id:
            vacunas = Vaccine.objects.filter(pet_id=pet_id,
                                             pet__owner=request.user)
        else:
            vacunas = Vaccine.objects.filter(pet__owner=request.user)
        return Response(VacunaSerializer(vacunas, many=True).data)

    serializer = VacunaSerializer(data=request.data)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data, status=status.HTTP_201_CREATED)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


# ── CONSULTAS ─────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def consultas_lista(request):
    consultas = MedicalConsultation.objects.filter(
        appointment__user=request.user
    )
    return Response(MedicalConsultationSerializer(consultas, many=True).data)


# ── PERFIL ────────────────────────────────────────────────────────

@api_view(['GET', 'PUT'])
@permission_classes([IsAuthenticated])
def perfil_detalle(request):
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    if request.method == 'GET':
        return Response(UserProfileSerializer(profile).data)
    serializer = UserProfileSerializer(profile, data=request.data, partial=True)
    if serializer.is_valid():
        serializer.save()
        return Response(serializer.data)
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def servicios_con_vets(request):
    """Servicios activos con sus veterinarios"""
    servicios = Service.objects.filter(is_active=True)
    result = []
    for s in servicios:
        vets = Veterinarian.objects.filter(services=s, is_active=True)
        result.append({
            'id': s.id,
            'name': s.name,
            'description': s.description,
            'duration': s.duration,
            'price': str(s.price),
            'icon': s.icon,
            'veterinarios': VeterinarianSerializer(vets, many=True).data,
        })
    return Response(result)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def historial_medico(request):
    citas = Appointment.objects.filter(
        user=request.user,
        status='completed'
    ).order_by('-date')

    result = []
    for cita in citas:
        item = AppointmentSerializer(cita).data
        
        # Servicio
        if cita.service_id:
            try:
                servicio = Service.objects.get(id=cita.service_id)
                item['servicio_nombre'] = servicio.name
            except:
                item['servicio_nombre'] = ''
        else:
            item['servicio_nombre'] = ''

        # Veterinario
        if cita.veterinarian_id:
            try:
                vet = Veterinarian.objects.get(id=cita.veterinarian_id)
                item['veterinario_nombre'] = vet.name
            except:
                item['veterinario_nombre'] = ''
        else:
            item['veterinario_nombre'] = ''

        # Consulta
        try:
            consulta = cita.consultation
            item['consulta'] = {
                'id': consulta.id,
                'diagnostico': consulta.diagnosis,
                'tratamiento': consulta.treatment,
                'motivo': consulta.reason,
                'notas': consulta.notes,
                'peso': str(consulta.weight_at_visit) if consulta.weight_at_visit else None,
                'temperatura': str(consulta.temperature) if consulta.temperature else None,
                'proxima_visita': str(consulta.next_visit) if consulta.next_visit else None,
            }
            try:
                receta = consulta.prescription
                item['consulta']['receta'] = {
                    'id': receta.id,
                    'instrucciones': receta.general_instructions,
                    'advertencias': receta.warnings,
                    'medicamentos': [
                        {
                            'medicamento': med.medication,
                            'dosis': med.dose,
                            'frecuencia': med.frequency,
                            'duracion': med.duration,
                            'instrucciones': med.instructions,
                        }
                        for med in receta.items.all()
                    ]
                }
            except:
                item['consulta']['receta'] = None
        except:
            item['consulta'] = None

        result.append(item)

    return Response(result)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def cita_detalle_completo(request, pk):
    import traceback
    try:
        cita = get_object_or_404(Appointment, pk=pk, user=request.user)
        data = AppointmentSerializer(cita).data

        # Servicio
        if cita.service_id:
            try:
                servicio = Service.objects.get(id=cita.service_id)
                data['servicio_nombre'] = servicio.name
                data['servicio_duracion'] = servicio.duration
                data['servicio_precio'] = str(servicio.price)
            except:
                pass

        # Veterinario
        if cita.veterinarian_id:
            try:
                vet = Veterinarian.objects.get(id=cita.veterinarian_id)
                data['veterinario_nombre'] = vet.name
                data['veterinario_foto'] = (
                    request.build_absolute_uri(vet.photo.url)
                    if vet.photo else None
                )
            except Exception:
                data['veterinario_nombre'] = ''
                data['veterinario_foto'] = None
        else:
            data['veterinario_nombre'] = ''
            data['veterinario_foto'] = None

        # Consulta
        try:
            consulta = cita.consultation
            data['consulta'] = {
                'id': consulta.id,
                'motivo': consulta.reason,
                'sintomas': consulta.symptoms,
                'diagnostico': consulta.diagnosis,
                'tratamiento': consulta.treatment,
                'notas': consulta.notes,
                'peso': str(consulta.weight_at_visit) if consulta.weight_at_visit else None,
                'temperatura': str(consulta.temperature) if consulta.temperature else None,
                'proxima_visita': str(consulta.next_visit) if consulta.next_visit else None,
            }
            try:
                receta = consulta.prescription
                data['consulta']['receta'] = {
                    'id': receta.id,
                    'instrucciones': receta.general_instructions,
                    'advertencias': receta.warnings,
                    'medicamentos': [
                        {
                            'medicamento': med.medication,
                            'dosis': med.dose,
                            'frecuencia': med.frequency,
                            'duracion': med.duration,
                            'instrucciones': med.instructions,
                        }
                        for med in receta.items.all()
                    ]
                }
            except:
                data['consulta']['receta'] = None
        except:
            data['consulta'] = None

    except Exception as e:
        print("ERROR cita_detalle_completo:", traceback.format_exc())
        return Response({'error': str(e)}, status=500)

    return Response(data)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def update_avatar(request):
    if 'avatar' not in request.FILES:
        return Response({'error': 'No se envió imagen'}, status=status.HTTP_400_BAD_REQUEST)
    from booking.models import UserProfile
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    profile.avatar = request.FILES['avatar']
    profile.save()
    return Response({'message': 'Avatar actualizado'})

from booking.models import Hospitalization, HospitalizationMonitoring, HospitalizationTreatment, HospitalizationOrder

@api_view(['GET'])
@authentication_classes([TokenAuthentication])
@permission_classes([IsAuthenticated])
def hospitalizaciones_lista(request):
    """Hospitalizaciones de las mascotas del usuario autenticado"""
    mascotas = Pet.objects.filter(owner=request.user)
    hospitalizaciones = Hospitalization.objects.filter(
        pet__in=mascotas
    ).select_related('pet', 'veterinarian').order_by('-admission_date')

    data = []
    for h in hospitalizaciones:
        data.append({
            'id': h.id,
            'pet_id': h.pet.id,
            'pet_name': h.pet.name,
            'pet_type': h.pet.pet_type,
            'pet_photo': request.build_absolute_uri(h.pet.photo.url) if h.pet.photo else None,
            'veterinarian_name': h.veterinarian.name if h.veterinarian else None,
            'reason': h.reason,
            'initial_diagnosis': h.initial_diagnosis,
            'admission_date': h.admission_date.isoformat(),
            'discharge_date': h.discharge_date.isoformat() if h.discharge_date else None,
            'patient_status': h.patient_status,
            'patient_status_display': h.get_patient_status_display(),
            'status': h.status,
            'status_display': h.get_status_display(),
            'notes': h.notes,
            'monitoring_count': h.monitoring_records.count(),
        })
    return Response(data)


@api_view(['GET'])
@authentication_classes([TokenAuthentication])
@permission_classes([IsAuthenticated])
def hospitalizacion_detalle(request, pk):
    """Detalle completo de una hospitalización"""
    try:
        h = Hospitalization.objects.select_related(
            'pet', 'veterinarian'
        ).get(pk=pk, pet__owner=request.user)
    except Hospitalization.DoesNotExist:
        return Response({'error': 'No encontrada'}, status=404)

    # Monitoreos
    monitoring = []
    for rec in h.monitoring_records.all():
        monitoring.append({
            'id': rec.id,
            'recorded_at': rec.recorded_at.isoformat(),
            'temperature': str(rec.temperature) if rec.temperature else None,
            'heart_rate': rec.heart_rate,
            'respiratory_rate': rec.respiratory_rate,
            'weight': str(rec.weight) if rec.weight else None,
            'general_status': rec.general_status,
            'general_status_display': rec.get_general_status_display(),
            'observations': rec.observations,
        })

    # Tratamientos
    treatments = []
    for t in h.treatments.all():
        treatments.append({
            'id': t.id,
            'medication': t.medication,
            'dose': t.dose,
            'frequency': t.frequency,
            'route': t.get_route_display(),
            'status': t.status,
            'status_display': t.get_status_display(),
            'notes': t.notes,
        })

    # Orden médica
    order = None
    try:
        o = h.medical_order
        order = {
            'fluid_therapy': o.fluid_therapy,
            'fluid_therapy_detail': o.fluid_therapy_detail,
            'diet': o.get_diet_display(),
            'diet_notes': o.diet_notes,
            'laboratory': o.laboratory,
            'laboratory_detail': o.laboratory_detail,
            'xray': o.xray,
            'xray_detail': o.xray_detail,
            'ultrasound': o.ultrasound,
            'ultrasound_detail': o.ultrasound_detail,
            'special_instructions': o.special_instructions,
        }
    except HospitalizationOrder.DoesNotExist:
        pass

    data = {
        'id': h.id,
        'pet_id': h.pet.id,
        'pet_name': h.pet.name,
        'pet_type': h.pet.pet_type,
        'pet_photo': request.build_absolute_uri(h.pet.photo.url) if h.pet.photo else None,
        'veterinarian_name': h.veterinarian.name if h.veterinarian else None,
        'reason': h.reason,
        'initial_diagnosis': h.initial_diagnosis,
        'admission_date': h.admission_date.isoformat(),
        'discharge_date': h.discharge_date.isoformat() if h.discharge_date else None,
        'patient_status': h.patient_status,
        'patient_status_display': h.get_patient_status_display(),
        'status': h.status,
        'status_display': h.get_status_display(),
        'notes': h.notes,
        'monitoring': monitoring,
        'treatments': treatments,
        'order': order,
    }
    return Response(data)