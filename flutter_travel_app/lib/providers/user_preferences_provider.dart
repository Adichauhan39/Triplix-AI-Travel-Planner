import 'package:flutter/foundation.dart';
import '../models/user_preferences.dart';

class UserPreferencesProvider with ChangeNotifier {
  final UserPreferences _preferences = UserPreferences();

  UserPreferences get preferences => _preferences;

  void updateDestination(String destination) {
    _preferences.destination = destination;
    notifyListeners();
  }

  void updateDestinationPreferences({
    List<String>? climates,
    List<String>? terrains,
    List<String>? cultures,
    List<String>? sunActivities,
  }) {
    if (climates != null) _preferences.selectedClimates = climates;
    if (terrains != null) _preferences.selectedTerrains = terrains;
    if (cultures != null) _preferences.selectedCultures = cultures;
    if (sunActivities != null) {
      _preferences.selectedSunActivities = sunActivities;
    }
    notifyListeners();
  }

  void updateBudget(double budget) {
    _preferences.budget = budget;
    notifyListeners();
  }

  void updateActivities(List<String> activities) {
    _preferences.selectedActivities = activities;
    notifyListeners();
  }

  void updateTransport(List<String> transport) {
    _preferences.selectedTransport = transport;
    notifyListeners();
  }

  void updateAccommodation(List<String> accommodation) {
    _preferences.selectedAccommodation = accommodation;
    notifyListeners();
  }

  void updateAdditionalContext({
    String? companion,
    String? occasion,
    String? experience,
    List<String>? accessibility,
    List<String>? dietary,
    List<String>? medical,
    List<String>? languages,
  }) {
    if (companion != null) _preferences.companion = companion;
    if (occasion != null) _preferences.occasion = occasion;
    if (experience != null) _preferences.experience = experience;
    if (accessibility != null) {
      _preferences.selectedAccessibility = accessibility;
    }
    if (dietary != null) _preferences.selectedDietary = dietary;
    if (medical != null) _preferences.selectedMedical = medical;
    if (languages != null) _preferences.selectedLanguages = languages;
    notifyListeners();
  }

  void updateDates(DateTime checkIn, DateTime checkOut) {
    _preferences.checkInDate = checkIn;
    _preferences.checkOutDate = checkOut;
    notifyListeners();
  }

  void updateNumberOfPeople(int people) {
    _preferences.numberOfPeople = people;
    notifyListeners();
  }

  void clearAll() {
    _preferences.destination = null;
    _preferences.budget = null;
    _preferences.selectedActivities = [];
    _preferences.selectedTransport = [];
    _preferences.selectedAccommodation = [];
    _preferences.selectedClimates = [];
    _preferences.selectedTerrains = [];
    _preferences.selectedCultures = [];
    _preferences.companion = null;
    _preferences.occasion = null;
    _preferences.experience = null;
    _preferences.selectedAccessibility = [];
    _preferences.selectedDietary = [];
    _preferences.selectedMedical = [];
    _preferences.selectedLanguages = [];
    _preferences.checkInDate = null;
    _preferences.checkOutDate = null;
    _preferences.numberOfPeople = null;
    notifyListeners();
  }
}
