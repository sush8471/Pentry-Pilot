import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dietary_profile.dart';

/// State of the user's dietary profiles.
class ProfileState {
  final List<DietaryProfile> profiles;
  final DietaryProfile? activeProfile;

  const ProfileState({
    required this.profiles,
    this.activeProfile,
  });

  ProfileState copyWith({
    List<DietaryProfile>? profiles,
    DietaryProfile? activeProfile,
  }) {
    return ProfileState(
      profiles: profiles ?? this.profiles,
      activeProfile: activeProfile ?? this.activeProfile,
    );
  }
}

/// Notifier managing profile persistence and active profile switching.
class ProfileNotifier extends StateNotifier<ProfileState> {
  final ProfileService _service;

  ProfileNotifier(this._service)
      : super(ProfileState(
          profiles: _service.allProfiles,
          activeProfile: _service.activeProfile,
        )) {
    // If no profiles exist, seed a sensible default Celiac / Nut / Dairy profile
    if (_service.allProfiles.isEmpty) {
      _service.create(
        name: 'Default (Gluten & Nuts)',
        activeAllergenCodes: ['PEANUT', 'TREENUT', 'GLUTEN', 'WHEAT'],
        strictMode: true,
      );
      _sync();
    }
  }

  void _sync() {
    state = ProfileState(
      profiles: _service.allProfiles,
      activeProfile: _service.activeProfile,
    );
  }

  DietaryProfile createProfile({
    required String name,
    required List<String> activeAllergenCodes,
    bool strictMode = false,
  }) {
    final created = _service.create(
      name: name,
      activeAllergenCodes: activeAllergenCodes,
      strictMode: strictMode,
    );
    _sync();
    return created;
  }

  void updateProfile(
    String id, {
    String? name,
    List<String>? activeAllergenCodes,
    bool? strictMode,
  }) {
    _service.update(
      id,
      name: name,
      activeAllergenCodes: activeAllergenCodes,
      strictMode: strictMode,
    );
    _sync();
  }

  void setActive(String id) {
    _service.setActive(id);
    _sync();
  }

  void deleteProfile(String id) {
    _service.delete(id);
    _sync();
  }
}

/// Global provider for the ProfileService singleton
final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

/// Global provider for dietary profile state
final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  final service = ref.watch(profileServiceProvider);
  return ProfileNotifier(service);
});

