import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/dietary_profile.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const Map<String, String> _allergenLabels = {
    'MILK': 'Milk & Dairy',
    'EGG': 'Egg & Derivatives',
    'PEANUT': 'Peanuts & Groundnuts',
    'TREENUT': 'Tree Nuts (Almond, Cashew, Walnut)',
    'WHEAT': 'Wheat (FDA Standard)',
    'GLUTEN': 'Gluten (Wheat, Barley, Rye)',
    'SOY': 'Soy & Soybeans',
    'FISH': 'Fish & Marine extracts',
    'SHELLFISH': 'Crustaceans & Molluscs',
    'SESAME': 'Sesame & Tahini',
  };

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(profileProvider);
    final activeProfile = profileState.activeProfile;

    return Scaffold(
      backgroundColor: const Color(0xFF121417),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1E23),
        elevation: 0,
        title: const Text(
          'Dietary Profiles',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.greenAccent),
            tooltip: 'New Profile',
            onPressed: () => _showCreateProfileDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // 100% Offline Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2822),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '100% Offline • Private & On-Device Storage',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Active Profile Card
          if (activeProfile != null) ...[
            const Text(
              'ACTIVE SCANNING PROFILE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            _buildActiveProfileCard(context, activeProfile),
            const SizedBox(height: 26),
          ],

          // All Profiles
          const Text(
            'SAVED PROFILES',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          for (final profile in profileState.profiles)
            _buildProfileTile(context, profile, activeProfile?.id == profile.id),
        ],
      ),
    );
  }

  Widget _buildActiveProfileCard(BuildContext context, DietaryProfile profile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withOpacity(0.08),
            blurRadius: 16,
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
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF243429),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.activeAllergenCodes.length} active restrictions',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Strict mode indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: profile.strictMode ? Colors.redAccent.withOpacity(0.2) : Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: profile.strictMode ? Colors.redAccent : Colors.white24,
                  ),
                ),
                child: Text(
                  profile.strictMode ? 'STRICT' : 'STANDARD',
                  style: TextStyle(
                    color: profile.strictMode ? Colors.redAccent : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),

          // Allergen chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in kSupportedAllergenCodes)
                _buildAllergenToggleChip(
                  code: code,
                  isSelected: profile.activeAllergenCodes.contains(code),
                  onTap: () {
                    final updated = List<String>.from(profile.activeAllergenCodes);
                    if (updated.contains(code)) {
                      updated.remove(code);
                    } else {
                      updated.add(code);
                    }
                    ref.read(profileProvider.notifier).updateProfile(
                          profile.id,
                          activeAllergenCodes: updated,
                        );
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Strict Mode Toggle Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Strict Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Treat ambiguous & cross-contact labels as DANGER',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: profile.strictMode,
                activeColor: Colors.redAccent,
                onChanged: (val) {
                  ref.read(profileProvider.notifier).updateProfile(
                        profile.id,
                        strictMode: val,
                      );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTile(BuildContext context, DietaryProfile profile, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.greenAccent.withOpacity(0.5) : Colors.white10,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          isActive ? Icons.radio_button_checked : Icons.radio_button_off,
          color: isActive ? Colors.greenAccent : Colors.white38,
        ),
        title: Text(
          profile.name,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${profile.activeAllergenCodes.length} allergens • ${profile.strictMode ? "Strict" : "Standard"}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: isActive
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.white38, size: 20),
                onPressed: () {
                  ref.read(profileProvider.notifier).deleteProfile(profile.id);
                },
              ),
        onTap: () {
          ref.read(profileProvider.notifier).setActive(profile.id);
        },
      ),
    );
  }

  Widget _buildAllergenToggleChip({
    required String code,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final label = _allergenLabels[code] ?? code;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B1D1D) : const Color(0xFF22262C),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.redAccent : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              color: isSelected ? Colors.redAccent : Colors.white38,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final selectedCodes = <String>{'PEANUT', 'TREENUT'};
    bool strict = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B1E23),
          title: const Text('Create Profile', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Profile Name (e.g. Celiac Kid)',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.greenAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Select Allergens:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final code in kSupportedAllergenCodes)
                      FilterChip(
                        label: Text(_allergenLabels[code] ?? code),
                        selected: selectedCodes.contains(code),
                        selectedColor: Colors.redAccent.withOpacity(0.3),
                        checkmarkColor: Colors.redAccent,
                        backgroundColor: const Color(0xFF22262C),
                        labelStyle: const TextStyle(color: Colors.white, fontSize: 11),
                        onSelected: (sel) {
                          setDialogState(() {
                            if (sel) {
                              selectedCodes.add(code);
                            } else {
                              selectedCodes.remove(code);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: strict,
                      activeColor: Colors.redAccent,
                      onChanged: (v) => setDialogState(() => strict = v ?? false),
                    ),
                    const Expanded(
                      child: Text('Strict Mode', style: TextStyle(color: Colors.white, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  ref.read(profileProvider.notifier).createProfile(
                        name: name,
                        activeAllergenCodes: selectedCodes.toList(),
                        strictMode: strict,
                      );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Save Profile', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}

