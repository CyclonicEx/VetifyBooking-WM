from rest_framework import serializers
from booking.models import (
    Appointment, Pet, Service, Veterinarian,
    ClinicSchedule, UserProfile, MedicalConsultation,
    MedicalPrescription, PrescriptionItem, Vaccine,
)
from datetime import date

class PetSerializer(serializers.ModelSerializer):
    age = serializers.SerializerMethodField()

    class Meta:
        model = Pet
        fields = '__all__'
        read_only_fields = ('id', 'owner')

    def get_age(self, obj):
        if obj.date_of_birth:
            today = date.today()
            return today.year - obj.date_of_birth.year - (
                (today.month, today.day) < (obj.date_of_birth.month, obj.date_of_birth.day)
            )
        return 0


class AppointmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Appointment
        fields = '__all__'
        read_only_fields = ('id', 'user', 'created_at')

    def validate(self, data):
        request = self.context.get('request')
        pet = data.get('pet') or (self.instance.pet if self.instance else None)
        date_ = data.get('date') or (self.instance.date if self.instance else None)
        time_ = data.get('time') or (self.instance.time if self.instance else None)
        vet = data.get('veterinarian')

        if pet and date_ and time_ and vet:
            qs = Appointment.objects.filter(
                veterinarian=vet, date=date_, time=time_
            ).exclude(status='cancelled')
            if self.instance:
                qs = qs.exclude(pk=self.instance.pk)
            if qs.exists():
                raise serializers.ValidationError({
                    'non_field_errors': ['Ese veterinario ya tiene una cita en ese horario.']
                })
        return data


class ServiceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Service
        fields = '__all__'


class VeterinarianSerializer(serializers.ModelSerializer):
    get_specialty_display = serializers.SerializerMethodField()

    class Meta:
        model = Veterinarian
        fields = '__all__'

    def get_get_specialty_display(self, obj):
        return obj.get_specialty_display()


class ClinicScheduleSerializer(serializers.ModelSerializer):
    get_day_of_week_display = serializers.SerializerMethodField()

    class Meta:
        model = ClinicSchedule
        fields = '__all__'

    def get_get_day_of_week_display(self, obj):
        return obj.get_day_of_week_display()


class UserProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserProfile
        fields = '__all__'
        read_only_fields = ('id', 'user')


class MedicalConsultationSerializer(serializers.ModelSerializer):
    class Meta:
        model = MedicalConsultation
        fields = '__all__'


class MedicalPrescriptionSerializer(serializers.ModelSerializer):
    class Meta:
        model = MedicalPrescription
        fields = '__all__'


class PrescriptionItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = PrescriptionItem
        fields = '__all__'


class VacunaSerializer(serializers.ModelSerializer):
    class Meta:
        model = Vaccine
        fields = '__all__'