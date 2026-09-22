import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('zettax.app/updates');
const _manifestUrl = 'https://zettax.app/updates/latest.json';

bool isEligibleZettaxUpdate(Map<String, dynamic> data, int installedCode) {
  final latestCode = data['versionCode'];
  final url = Uri.tryParse(data['apkUrl']?.toString() ?? '');
  final checksum = data['sha256']?.toString().toLowerCase() ?? '';
  return latestCode is int &&
      latestCode > installedCode &&
      url != null &&
      url.scheme == 'https' &&
      url.host == 'zettax.app' &&
      url.userInfo.isEmpty &&
      url.port == 443 &&
      url.path.startsWith('/downloads/') &&
      url.path.endsWith('.apk') &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum);
}

class AppUpdateHost extends StatefulWidget {
  const AppUpdateHost(
      {super.key, required this.child, required this.navigatorKey});
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends State<AppUpdateHost>
    with WidgetsBindingObserver {
  final _dio = Dio();
  Timer? _timer;
  bool _checking = false;
  DateTime? _lastCheck;
  int? _dismissedVersionCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted ||
        _checking ||
        (_lastCheck != null &&
            DateTime.now().difference(_lastCheck!) <
                const Duration(minutes: 5))) {
      return;
    }
    _checking = true;
    _lastCheck = DateTime.now();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _manifestUrl,
        options: Options(
          headers: {'Cache-Control': 'no-cache'},
          followRedirects: false,
        ),
      );
      final data = response.data;
      if (data == null) return;
      final installedCode = await _channel.invokeMethod<int>('versionCode');
      final url = Uri.tryParse(data['apkUrl']?.toString() ?? '');
      final checksum = data['sha256']?.toString().toLowerCase() ?? '';
      if (installedCode == null ||
          !isEligibleZettaxUpdate(data, installedCode) ||
          data['versionCode'] == _dismissedVersionCode ||
          url == null ||
          !mounted) {
        return;
      }
      await _showUpdate(data, url, checksum);
    } catch (_) {
      // Updates should never prevent the app from starting or trading.
    } finally {
      _checking = false;
    }
  }

  Future<void> _showUpdate(
      Map<String, dynamic> data, Uri url, String checksum) async {
    final dialogHost = widget.navigatorKey.currentState?.overlay?.context;
    if (dialogHost == null) return;
    var downloading = false;
    var progress = 0.0;
    String? error;
    await showDialog<void>(
      context: dialogHost,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: const Text('Zettax update available'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version ${data['versionName'] ?? ''} is ready.'),
                if ((data['notes']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(data['notes'].toString()),
                ],
                if (downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                      value: progress == 0 ? null : progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).round()}% downloaded'),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ]),
          actions: [
            TextButton(
              onPressed: downloading
                  ? null
                  : () {
                      _dismissedVersionCode = data['versionCode'] as int?;
                      Navigator.pop(dialogContext);
                    },
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: downloading
                  ? null
                  : () async {
                      update(() {
                        downloading = true;
                        error = null;
                        progress = 0;
                      });
                      try {
                        final directory = await _channel
                            .invokeMethod<String>('cacheDirectory');
                        if (directory == null) {
                          throw StateError('Update storage is unavailable.');
                        }
                        final apk = File(
                            '$directory/zettax-${data['versionCode']}.apk');
                        if (!await apk.exists() ||
                            (await sha256.bind(apk.openRead()).first)
                                    .toString() !=
                                checksum) {
                          await _dio.downloadUri(url, apk.path,
                              options: Options(followRedirects: false),
                              onReceiveProgress: (received, total) {
                            if (total > 0 && dialogContext.mounted) {
                              update(() => progress = received / total);
                            }
                          });
                        }
                        final actual = (await sha256.bind(apk.openRead()).first)
                            .toString();
                        if (actual != checksum) {
                          await apk.delete();
                          throw StateError(
                              'Update verification failed. Please try again.');
                        }
                        await _channel
                            .invokeMethod<void>('install', {'path': apk.path});
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } on PlatformException catch (e) {
                        if (dialogContext.mounted) {
                          update(() => error =
                              e.message ?? 'Unable to open the installer.');
                        }
                      } catch (_) {
                        if (dialogContext.mounted) {
                          update(() => error =
                              'The update could not be downloaded. Please try again.');
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          update(() => downloading = false);
                        }
                      }
                    },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
