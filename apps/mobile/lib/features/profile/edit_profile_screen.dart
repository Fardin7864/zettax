import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/funding/funding_repository.dart';

final profileAvatarProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, key) async {
  // Keyed by user and object so changing accounts/pictures cannot reuse an old image.
  final response = await ref.watch(apiClientProvider).get('/users/me/avatar',
      (value) => base64Decode(value['imageBase64'] as String));
  return response.data;
});

class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, required this.user, this.radius = 28});
  final CurrentUser? user;
  final double radius;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = user?.profile?.avatarObjectKey;
    final bytes = key == null
        ? null
        : ref.watch(profileAvatarProvider('${user!.id}:$key')).valueOrNull;
    return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0x33F8B425),
        backgroundImage: bytes == null ? null : MemoryImage(bytes),
        child: bytes == null
            ? const Icon(Icons.person, color: Colors.amber)
            : null);
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.user});
  final CurrentUser user;
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, address, district, country;
  DateTime? birth;
  String? gender;
  Uint8List? picture;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final profile = widget.user.profile;
    name = TextEditingController(text: profile?.fullName ?? '');
    address = TextEditingController(text: profile?.currentAddress ?? '');
    district = TextEditingController(text: profile?.district ?? '');
    country = TextEditingController(text: profile?.country ?? 'Bangladesh');
    birth = profile?.dateOfBirth;
    gender = ['Male', 'Female', 'Other', 'Prefer not to say']
            .contains(profile?.gender)
        ? profile?.gender
        : null;
  }

  @override
  void dispose() {
    for (final controller in [name, address, district, country]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> pickPicture() async {
    try {
      final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      screenshotImageType(bytes);
      if (bytes.length > 5 * 1024 * 1024) {
        throw Exception('Choose a picture smaller than 5 MB.');
      }
      if (mounted) setState(() => picture = bytes);
    } catch (_) {
      showTopNotification('Choose a PNG or JPEG picture up to 5 MB.',
          success: false);
    }
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    if (birth == null) {
      showTopNotification('Choose your date of birth.', success: false);
      return;
    }
    setState(() => saving = true);
    var detailsSaved = false;
    try {
      final client = ref.read(apiClientProvider);
      await client.post(
          '/users/me/profile',
          {
            'fullName': name.text.trim(),
            'dateOfBirth': birth!.toIso8601String().split('T').first,
            if (gender != null) 'gender': gender,
            'currentAddress': address.text.trim(),
            'district': district.text.trim(),
            'country': country.text.trim(),
          },
          (value) => value,
          receiveTimeout: const Duration(seconds: 60));
      detailsSaved = true;
      if (picture != null) {
        final type = screenshotImageType(picture!);
        await client.upload(
            '/users/me/avatar',
            FormData.fromMap({
              'file': MultipartFile.fromBytes(picture!,
                  filename: type == 'png' ? 'avatar.png' : 'avatar.jpg',
                  contentType: DioMediaType('image', type)),
            }),
            (value) => value);
      }
      ref.invalidate(currentUserProvider);
      if (mounted) {
        Navigator.pop(context);
        showTopNotification('Profile updated.', success: true);
      }
    } catch (error) {
      if (detailsSaved) ref.invalidate(currentUserProvider);
      showTopNotification(
          '${detailsSaved ? 'Details saved, but picture upload failed. ' : ''}${error is ApiFailure ? error.message : 'Could not save. Please try again.'}',
          success: false);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit profile')),
        body: Form(
            key: form,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Center(
                  child: picture == null
                      ? ProfileAvatar(user: widget.user, radius: 48)
                      : CircleAvatar(
                          radius: 48, backgroundImage: MemoryImage(picture!))),
              TextButton.icon(
                  onPressed: saving ? null : pickPicture,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Change profile picture')),
              const SizedBox(height: 12),
              TextFormField(
                  controller: name,
                  enabled: !saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter your name' : null),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date of birth'),
                  subtitle: Text(birth?.toIso8601String().split('T').first ??
                      'Choose date'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: saving
                      ? null
                      : () async {
                          final date = await showDatePicker(
                              context: context,
                              initialDate: birth ?? DateTime(2000),
                              firstDate: DateTime(1900),
                              lastDate: DateTime.now());
                          if (date != null && mounted) {
                            setState(() => birth = date);
                          }
                        }),
              DropdownButtonFormField<String>(
                  initialValue: gender,
                  decoration:
                      const InputDecoration(labelText: 'Gender (optional)'),
                  items: ['Male', 'Female', 'Other', 'Prefer not to say']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: saving ? null : (v) => setState(() => gender = v)),
              const SizedBox(height: 16),
              TextFormField(
                  controller: address,
                  enabled: !saving,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Address')),
              TextFormField(
                  controller: district,
                  enabled: !saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'District')),
              TextFormField(
                  controller: country,
                  enabled: !saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Country'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter country' : null),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Saving…' : 'Save profile')),
            ])),
      );
}
