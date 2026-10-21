import 'dart:io';

import 'package:cairn_sync/cairn_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/tokens.dart';
import 'device_identity.dart';
import 'project_store.dart';
import 'skill_store.dart';
import 'sync_service.dart';

/// Devices & sync (M7): this device's identity, pairing (offer paste +
/// SAS compare — v1 transports the offer by copy/paste; the trust comes
/// from the keys and the compared code, not the channel), the paired
/// device list, manual "sync now" over LAN/Tailscale, and the sync
/// server toggle that lets the paired peer initiate.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    super.key,
    required this.projects,
    required this.skills,
    required this.baseDir,
    required this.seedStore,
  });

  final ProjectStore projects;
  final SkillStore skills;
  final Directory baseDir;
  final SeedStore seedStore;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  DeviceKeyPair? _identity;
  String _displayName = '';
  List<PairedDevice> _paired = const [];
  int _trashCount = 0;
  bool _serverOn = false;
  SyncServer? _server;
  String? _offerText;
  PairingSession? _pendingSession;
  String _status = '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pasteController = TextEditingController();
  final Map<String, TextEditingController> _hostControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _server?.close();
    _nameController.dispose();
    _pasteController.dispose();
    for (final c in _hostControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  SyncCoordinator _coordinator() => SyncCoordinator(
        projects: widget.projects,
        skills: widget.skills,
        baseDir: widget.baseDir,
        deviceId: _identity!.deviceId,
      );

  Future<void> _load() async {
    final identity =
        await DeviceIdentityService(widget.seedStore).loadOrCreate();
    final name = await DeviceProfileStore(widget.baseDir).loadName();
    final paired = await PairedDevicesStore(widget.baseDir).list();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _displayName = name;
      _nameController.text = name;
      _paired = paired;
    });
    await _reloadTrash();
  }

  Future<void> _reloadTrash() async {
    if (_identity == null) return;
    final trash = await _coordinator().trash();
    if (mounted) {
      setState(() {
        _trashCount = trash.length;
      });
    }
  }

  void _showStatus(String message) {
    if (mounted) {
      setState(() {
        _status = message;
      });
    }
  }

  Future<void> _makeOffer() async {
    final identity = _identity!;
    final offer = PairingOffer(
      identity: DeviceIdentity(
        deviceId: identity.deviceId,
        publicKeyBytes: identity.publicKeyBytes,
        displayName: _displayName,
      ),
      nonce: secureRandomBytes(16),
    );
    setState(() {
      _offerText = offer.encode();
    });
  }

  Future<void> _inspectOffer() async {
    try {
      final offer = PairingOffer.decode(_pasteController.text.trim());
      final session =
          await PairingSession.fromOffer(local: _identity!, offer: offer);
      setState(() {
        _pendingSession = session;
      });
    } on FormatException catch (e) {
      _showStatus('پیشنهاد نامعتبر است: ${e.message}');
    }
  }

  Future<void> _confirmPairing() async {
    final session = _pendingSession;
    if (session == null) return;
    await PairedDevicesStore(widget.baseDir).add(session.confirm());
    final paired = await PairedDevicesStore(widget.baseDir).list();
    if (!mounted) return;
    setState(() {
      _paired = paired;
      _pendingSession = null;
      _pasteController.clear();
    });
    _showStatus('دستگاه جفت شد.');
  }

  Future<void> _syncNow(PairedDevice peer) async {
    final host = _hostControllers[peer.identity.deviceId]?.text.trim() ?? '';
    if (host.isEmpty) {
      _showStatus('اول نشانی (IP) دستگاه را وارد کن.');
      return;
    }
    _showStatus('در حال سینک…');
    try {
      final coordinator = _coordinator();
      final records = await coordinator.buildRecords();
      final result = await syncWithPeer(
        host: host,
        port: 47800,
        local: _identity!,
        peer: peer,
        localRecords: records,
      );
      final report = await coordinator.applyResult(result);
      // Remember the working host for next time.
      await PairedDevicesStore(widget.baseDir).add(PairedDevice(
        identity: peer.identity,
        pairedAtIso: peer.pairedAtIso,
        endpoints: [host],
      ));
      await _reloadTrash();
      _showStatus('سینک انجام شد — پروژه: ${report.projectsApplied}، '
          'مهارت: ${report.skillsApplied}، '
          'تعارض تازه: ${report.conflictsCreated}، '
          'حذف‌شده: ${report.deleted}');
    } catch (e) {
      _showStatus('سینک ناموفق بود: $e');
    }
  }

  Future<void> _toggleServer(bool on) async {
    if (on) {
      final server = SyncServer();
      try {
        await server.start(
          local: _identity!,
          allowedPeers: _paired,
          loadRecords: () => _coordinator().buildRecords(),
          onSync: (result) async {
            final report = await _coordinator().applyResult(result);
            _showStatus('سینک ورودی انجام شد — پروژه: '
                '${report.projectsApplied}، تعارض: '
                '${report.conflictsCreated}، حذف: ${report.deleted}');
            await _reloadTrash();
          },
        );
        _server = server;
        setState(() {
          _serverOn = true;
        });
      } catch (e) {
        _showStatus('سرور سینک شروع نشد: $e');
      }
    } else {
      await _server?.close();
      _server = null;
      setState(() {
        _serverOn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = _identity;
    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(CairnSpacing.lg),
      children: [
        Text('این دستگاه', style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        SelectableText('شناسه: ${identity.deviceId}'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'نام نمایشی'),
              ),
            ),
            const SizedBox(width: CairnSpacing.sm),
            FilledButton(
              onPressed: () async {
                await DeviceProfileStore(widget.baseDir)
                    .saveName(_nameController.text.trim());
                setState(() {
                  _displayName = _nameController.text.trim();
                });
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
        const Divider(height: CairnSpacing.xxl),
        Text('جفت‌سازی دستگاه تازه', style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.xs),
        const Text('در یک دستگاه «ساخت پیشنهاد» را بزن و متنش را اینجا '
            'بچسبان؛ در دستگاه دیگر هم همین کار را برعکس انجام بده. '
            'کد ۶ رقمی باید در هر دو دستگاه یکسان باشد.'),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: CairnSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _makeOffer,
              icon: const Icon(Icons.qr_code_2_outlined),
              label: const Text('ساخت پیشنهاد جفت‌سازی'),
            ),
            if (_offerText != null)
              OutlinedButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _offerText!)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('کپی پیشنهاد'),
              ),
          ],
        ),
        if (_offerText != null) ...[
          const SizedBox(height: CairnSpacing.sm),
          SelectableText(_offerText!,
              style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: CairnSpacing.md),
        TextField(
          controller: _pasteController,
          maxLines: 3,
          decoration: const InputDecoration(
              labelText: 'پیشنهاد دستگاه دیگر را اینجا بچسبان'),
        ),
        const SizedBox(height: CairnSpacing.sm),
        OutlinedButton(
          onPressed: _inspectOffer,
          child: const Text('بررسی پیشنهاد'),
        ),
        if (_pendingSession != null) ...[
          const SizedBox(height: CairnSpacing.md),
          Text('کد تأیید (باید با دستگاه دیگر یکسان باشد):',
              style: theme.textTheme.bodyMedium),
          Text(_pendingSession!.sas,
              style: theme.textTheme.headlineMedium),
          FilledButton(
            onPressed: _confirmPairing,
            child: const Text('کدها یکسان‌اند — جفت کن'),
          ),
        ],
        const Divider(height: CairnSpacing.xxl),
        Text('دستگاه‌های جفت‌شده', style: theme.textTheme.titleMedium),
        if (_paired.isEmpty)
          const Text('هنوز دستگاهی جفت نشده است.')
        else
          for (final peer in _paired)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(CairnSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.identity.displayName.isEmpty
                        ? peer.identity.deviceId
                        : peer.identity.displayName),
                    Text(peer.identity.deviceId,
                        style: theme.textTheme.bodySmall),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hostControllers.putIfAbsent(
                              peer.identity.deviceId,
                              () => TextEditingController(
                                  text: peer.endpoints.isEmpty
                                      ? ''
                                      : peer.endpoints.first),
                            ),
                            decoration: const InputDecoration(
                                labelText: 'نشانی IP / Tailscale'),
                          ),
                        ),
                        const SizedBox(width: CairnSpacing.sm),
                        FilledButton.icon(
                          onPressed: () => _syncNow(peer),
                          icon: const Icon(Icons.sync),
                          label: const Text('سینک کن'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: 'لغو جفت‌شدن',
                          onPressed: () async {
                            await PairedDevicesStore(widget.baseDir)
                                .remove(peer.identity.deviceId);
                            final paired = await PairedDevicesStore(
                                    widget.baseDir)
                                .list();
                            if (mounted) {
                              setState(() {
                                _paired = paired;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const Divider(height: CairnSpacing.xxl),
        SwitchListTile(
          title: const Text('سرور سینک (پذیرش سینک از دستگاه جفت‌شده)'),
          subtitle: const Text('پورت ۴۷۸۰۰ — فقط دستگاه‌های جفت‌شده'),
          value: _serverOn,
          onChanged: _toggleServer,
        ),
        if (_trashCount > 0)
          Text('سطل زبالهٔ سینک: $_trashCount مورد حذف‌شده (۳۰ روز نگه '
              'داشته می‌شود).'),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.md),
          Text(_status),
        ],
      ],
    );
  }
}
