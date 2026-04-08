from django.urls import path
from . import views

urlpatterns = [
    # Auth
    path('login/', views.api_login, name='api-login'),
    path('register/', views.api_register, name='api-register'),
    path('me/', views.mi_cuenta, name='api-me'),

    # Mascotas
    path('mascotas/', views.mascotas_lista, name='mascotas-lista'),
    path('mascotas/<int:pk>/', views.mascota_detalle, name='mascota-detalle'),

    # Citas
    path('citas/', views.citas_lista, name='citas-lista'),
    path('citas/<int:pk>/', views.cita_detalle, name='cita-detalle'),

    # Servicios
    path('servicios/', views.servicios_lista, name='servicios-lista'),

    # Veterinarios
    path('veterinarios/', views.veterinarios_lista, name='veterinarios-lista'),
    path('veterinarios/por-servicio/<int:service_id>/', views.vets_por_servicio, name='vets-por-servicio'),

    # Horarios
    path('horarios/', views.horarios_lista, name='horarios-lista'),

    # Slots disponibles
    path('available_slots/', views.available_slots, name='available-slots'),

    # Vacunas
    path('vacunas/', views.vacunas_lista, name='vacunas-lista'),

    # Consultas
    path('consultas/', views.consultas_lista, name='consultas-lista'),

    # Perfil
    path('perfil/', views.perfil_detalle, name='perfil-detalle'),
    
    path('servicios-con-vets/', views.servicios_con_vets, name='servicios-con-vets'),
    path('citas/<int:pk>/detalle/', views.cita_detalle_completo, name='cita-detalle-completo'),
    path('historial-medico/', views.historial_medico, name='historial-medico'),
    path('profile/avatar/', views.update_avatar, name='update-avatar'),
]