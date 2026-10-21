import 'dart:io';

import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_sync/cairn_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'device_identity.dart';
import 'project_store.dart';
import 'skill_store.dart';
import 'sync_runner.dart';
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
    required this.registry,
    this.embedded = false,
  });

  final ProjectStore projects;
  final SkillStore skills;
  final Directory baseDir;
  final SeedStore seedStore;

  /// True when hosted inside the Settings screen's scroll view: the
  /// internal list shrinks to fit instead of scrolling on its own.
  final bool embedded;

  /// This device's tool registry: what the overflow server can execute
  /// for paired peers (subject to the owner's switches below).
  final ToolRegistry registry;

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

  // Overflow (M8) state.
  bool _overflowOn = false;
  bool _overflowSensitive = false;
  OverflowServer? _overflowServer;
  final TextEditingController _ramController = TextEditingController();
  final TextEditingController _diskController = TextEditingController();
  bool _hasGpu = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _server?.close();
    _overflowServer?.close();
    _nameController.dispose();
    _pasteController.dispose();
    _ramController.dispose();
    _diskController.dispose();
    for (final c in _hostControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// This device's capabilities for routing: CPU cores are measured;
  /// RAM/disk/GPU come from the owner's declared specs (never invented).
  DeviceCapabilities _localCapabilities() {
    final specs = (
      ramMb: int.tryParse(_ramController.text) ?? 4096,
      freeDiskMb: int.tryParse(_diskController.text) ?? 10000,
      hasGpu: _hasGpu,
    );
    return DeviceCapabilities(
      deviceId: _identity!.deviceId,
      cpuCores: Platform.numberOfProcessors,
      ramMb: specs.ramMb,
      freeDiskMb: specs.freeDiskMb,
      hasGpu: specs.hasGpu,
      toolIds: widget.registry.all.map((t) => t.id).toSet(),
    );
  }

  SyncCoordinator _coordinator() => SyncCoordinator(
    projects: widget.projects,
    skills: widget.skills,
    baseDir: widget.baseDir,
    deviceId: _identity!.deviceId,
  );

  Future<void> _load() async {
    final identity = await DeviceIdentityService(widget.seedStore)
        .loadOrCreate();
    final name = await DeviceProfileStore(widget.baseDir).loadName();
    final paired = await PairedDevicesStore(widget.baseDir).list();
    final specs = await DeviceSpecsStore(widget.baseDir).load();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _displayName = name;
      _nameController.text = name;
      _paired = paired;
      _ramController.text = '${specs.ramMb}';
      _diskController.text = '${specs.freeDiskMb}';
      _hasGpu = specs.hasGpu;
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
    final s = S.of(context);
    try {
      final offer = PairingOffer.decode(_pasteController.text.trim());
      final session = await PairingSession.fromOffer(
        local: _identity!,
        offer: offer,
      );
      setState(() {
        _pendingSession = session;
      });
    } on FormatException catch (e) {
      _showStatus(s.dInvalidOffer(e.message));
    }
  }

  Future<void> _confirmPairing() async {
    final s = S.of(context);
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
    _showStatus(s.dPaired);
  }

  Future<void> _syncNow(PairedDevice peer) async {
    final s = S.of(context);
    final host = _hostControllers[peer.identity.deviceId]?.text.trim() ?? '';
    if (host.isEmpty) {
      _showStatus(s.dEnterHostFirst);
      return;
    }
    _showStatus(s.dSyncing);
    try {
      final report = await SyncRunner(
        projects: widget.projects,
        skills: widget.skills,
        baseDir: widget.baseDir,
        identity: _identity!,
      ).syncPeer(peer, host);
      await _reloadTrash();
      _showStatus(s.dSyncDone(report.projectsApplied, report.skillsApplied, report.conflictsCreated, report.deleted));
    } catch (e) {
      _showStatus(s.dSyncFailed('$e'));
    }
  }

  Future<void> _toggleServer(bool on) async {
    final s = S.of(context);
    if (on) {
      final server = SyncServer();
      try {
        await server.start(
          local: _identity!,
          allowedPeers: _paired,
          loadRecords: () => _coordinator().buildRecords(),
          onSync: (result) async {
            final report = await _coordinator().applyResult(result);
            _showStatus(s.dIncomingSync(report.projectsApplied, report.conflictsCreated, report.deleted));
            await _reloadTrash();
          },
        );
        _server = server;
        setState(() {
          _serverOn = true;
        });
      } catch (e) {
        _showStatus(s.dSyncServerFailed('$e'));
      }
    } else {
      await _server?.close();
      _server = null;
      setState(() {
        _serverOn = false;
      });
    }
  }

  Future<void> _toggleOverflow(bool on) async {
    final s = S.of(context);
    if (!on) {
      await _overflowServer?.close();
      _overflowServer = null;
      setState(() {
        _overflowOn = false;
      });
      return;
    }
    final server = OverflowServer();
    try {
      await server.start(
        local: _identity!,
        allowedPeers: _paired,
        allowedToolIds: widget.registry.all.map((t) => t.id).toSet(),
        sensitiveToolIds: {
          for (final t in widget.registry.all)
            if (t.sensitive) t.id,
        },
        allowSensitiveRemote: _overflowSensitive,
        localCapabilities: _localCapabilities(),
        handler: (toolId, arguments) async {
          final tool = widget.registry.lookup(toolId);
          if (tool == null) {
            return OverflowToolReply(
              ok: false,
              output: 'unknown tool: $toolId',
            );
          }
          final result = await tool.run(
            arguments,
            ToolContext(
              projectId: 'overflow',
              agentId: 'remote-peer',
              taskId: 'overflow-${DateTime.now().millisecondsSinceEpoch}',
            ),
          );
          return OverflowToolReply(ok: result.ok, output: result.output);
        },
      );
      _overflowServer = server;
      setState(() {
        _overflowOn = true;
      });
      _showStatus(s.dOverflowServerOn);
    } catch (e) {
      _showStatus(s.dOverflowServerFailed('$e'));
    }
  }

  /// Fetches a paired peer's capabilities over the overflow protocol
  /// and shows what the router would decide for two sample heavy steps.
  Future<void> _showPeerCapabilities(PairedDevice peer) async {
    final s = S.of(context);
    final host = _hostControllers[peer.identity.deviceId]?.text.trim() ?? '';
    if (host.isEmpty) {
      _showStatus(s.dEnterHostFirst);
      return;
    }
    _showStatus(s.dFetchingCaps);
    try {
      final client = await connectOverflow(
        host: host,
        port: 47801,
        local: _identity!,
        peer: peer,
      );
      final caps = await client.fetchCapabilities();
      await client.close();
      if (caps == null) {
        _showStatus(s.dNoCaps);
        return;
      }
      const balancer = LoadBalancer();
      final local = _localCapabilities();
      final candidates = [
        DeviceCandidate(caps: local, link: LinkKind.local),
        DeviceCandidate(caps: caps, link: classifyHost(host)),
      ];
      final heavyRam = balancer.decide(
        requirements: const StepRequirements(minRamMb: 16384),
        candidates: candidates,
      );
      final gpuStep = balancer.decide(
        requirements: const StepRequirements(needsGpu: true),
        candidates: candidates,
      );
      String verdict(RouteDecision d) => d.isBlocked
          ? s.dBlocked(d.unmet.join('؛ '))
          : (d.isLocal ? s.dRunsHere : s.dRunsThere);
      _showStatus(s.dCapsLine(peer.identity.displayName, caps.cpuCores, caps.ramMb, caps.hasGpu ? s.dHas : s.dHasNot, verdict(heavyRam), verdict(gpuStep)));
    } catch (e) {
      _showStatus(s.dCapsFailed('$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final identity = _identity;
    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(CairnSpacing.lg),
      children: [
        Text(s.dThisDevice, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        SelectableText(s.dDeviceId(identity.deviceId)),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(labelText: s.dDisplayName),
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
              child: Text(s.dSave),
            ),
          ],
        ),
        const Divider(height: CairnSpacing.xxl),
        Text(s.dPairNew, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.xs),
        Text(s.dPairHelp),
        const SizedBox(height: CairnSpacing.sm),
        Wrap(
          spacing: CairnSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _makeOffer,
              icon: const Icon(Icons.qr_code_2_outlined),
              label: Text(s.dMakeOffer),
            ),
            if (_offerText != null)
              OutlinedButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _offerText!)),
                icon: const Icon(Icons.copy_outlined),
                label: Text(s.dCopyOffer),
              ),
          ],
        ),
        if (_offerText != null) ...[
          const SizedBox(height: CairnSpacing.sm),
          SelectableText(_offerText!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: CairnSpacing.md),
        TextField(
          controller: _pasteController,
          maxLines: 3,
          decoration: InputDecoration(labelText: s.dPasteOffer),
        ),
        const SizedBox(height: CairnSpacing.sm),
        OutlinedButton(
          onPressed: _inspectOffer,
          child: Text(s.dInspectOffer),
        ),
        if (_pendingSession != null) ...[
          const SizedBox(height: CairnSpacing.md),
          Text(
            s.dSasLabel,
            style: theme.textTheme.bodyMedium,
          ),
          Text(_pendingSession!.sas, style: theme.textTheme.headlineMedium),
          FilledButton(
            onPressed: _confirmPairing,
            child: Text(s.dPairConfirm),
          ),
        ],
        const Divider(height: CairnSpacing.xxl),
        Text(s.dPairedDevices, style: theme.textTheme.titleMedium),
        if (_paired.isEmpty)
          Text(s.dNoPairedYet)
        else
          for (final peer in _paired)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(CairnSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.identity.displayName.isEmpty
                          ? peer.identity.deviceId
                          : peer.identity.displayName,
                    ),
                    Text(
                      peer.identity.deviceId,
                      style: theme.textTheme.bodySmall,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hostControllers.putIfAbsent(
                              peer.identity.deviceId,
                              () => TextEditingController(
                                text: peer.endpoints.isEmpty
                                    ? ''
                                    : peer.endpoints.first,
                              ),
                            ),
                            decoration: InputDecoration(labelText: s.dHostLabel),
                          ),
                        ),
                        const SizedBox(width: CairnSpacing.sm),
                        FilledButton.icon(
                          onPressed: () => _syncNow(peer),
                          icon: const Icon(Icons.sync),
                          label: Text(s.dSyncNow),
                        ),
                        const SizedBox(width: CairnSpacing.sm),
                        OutlinedButton.icon(
                          onPressed: () => _showPeerCapabilities(peer),
                          icon: const Icon(Icons.speed_outlined),
                          label: Text(s.dCapabilities),
                        ),
                        IconButton(
                          icon: const Icon(Icons.link_off),
                          tooltip: s.dUnpair,
                          onPressed: () async {
                            await PairedDevicesStore(widget.baseDir)
                                .remove(peer.identity.deviceId);
                            final paired = await PairedDevicesStore(
                              widget.baseDir,
                            ).list();
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
          title: Text(s.dSyncServerTitle),
          subtitle: Text(s.dSyncServerSub),
          value: _serverOn,
          onChanged: _toggleServer,
        ),
        const Divider(height: CairnSpacing.xxl),
        Text(s.dOverflowTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.xs),
        Text(s.dSpecsHelp),
        const SizedBox(height: CairnSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ramController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.dRamLabel),
              ),
            ),
            const SizedBox(width: CairnSpacing.sm),
            Expanded(
              child: TextField(
                controller: _diskController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.dDiskLabel),
              ),
            ),
          ],
        ),
        SwitchListTile(
          title: Text(s.dHasGpu),
          value: _hasGpu,
          onChanged: (v) {
            setState(() {
              _hasGpu = v;
            });
          },
        ),
        OutlinedButton(
          onPressed: () async {
            await DeviceSpecsStore(widget.baseDir).save(
              ramMb: int.tryParse(_ramController.text) ?? 4096,
              freeDiskMb: int.tryParse(_diskController.text) ?? 10000,
              hasGpu: _hasGpu,
            );
            _showStatus(s.dSpecsSaved);
          },
          child: Text(s.dSaveSpecs),
        ),
        SwitchListTile(
          title: Text(s.dOverflowServerTitle),
          subtitle: Text(s.dOverflowServerSub),
          value: _overflowOn,
          onChanged: _toggleOverflow,
        ),
        SwitchListTile(
          title: Text(s.dRemoteSensitiveTitle),
          subtitle: Text(s.dRemoteSensitiveSub),
          value: _overflowSensitive,
          onChanged: (v) {
            setState(() {
              _overflowSensitive = v;
            });
          },
        ),
        if (_trashCount > 0)
          Text(
            s.dTrashLine(_trashCount),
          ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.md),
          Text(_status),
        ],
      ],
    );
  }
}
