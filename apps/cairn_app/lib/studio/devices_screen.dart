import 'dart:async';
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

/// Devices & sync (M7 + M11 networking): this device's identity and
/// network status, AUTOMATIC discovery of the owner's other devices
/// on the LAN, in-network pairing with a SAS both screens show,
/// paired devices with auto-updated addresses, and the sync /
/// overflow servers — which now start by themselves when the studio
/// opens (v1 hid them behind manual toggles and asked the owner to
/// type IP addresses the app never displayed; the owner, reasonably,
/// reported "networking doesn't work at all").
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
  String _status = '';

  // Networking (M11).
  List<String> _lanIps = const [];
  LanState _lanState = LanState.offline;
  bool _visible = true;
  SyncServer? _server;
  bool _syncServerOn = false;
  OverflowServer? _overflowServer;
  bool _overflowOn = false;
  bool _overflowSensitive = false;
  PeerDiscovery? _discovery;
  List<DiscoveredPeer> _nearby = const [];
  StreamSubscription<List<DiscoveredPeer>>? _discoverySub;
  LanPairingServer? _pairingServer;
  IncomingPairing? _incoming;
  bool _pairingOut = false;

  // Legacy manual pairing (fallback, kept working).
  String? _offerText;
  PairingSession? _pendingSession;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pasteController = TextEditingController();
  final Map<String, TextEditingController> _hostControllers = {};
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
    _discoverySub?.cancel();
    _discovery?.close();
    _pairingServer?.close();
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
    final identity =
        await DeviceIdentityService(widget.seedStore).loadOrCreate();
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
    await _refreshNetwork();
    await _startNetworkServices();
    await _reloadTrash();
  }

  Future<void> _refreshNetwork() async {
    final ips = await lanIpv4Addresses();
    final state = await lanState();
    if (mounted) {
      setState(() {
        _lanIps = ips;
        _lanState = state;
      });
    }
  }

  List<String> get _myEndpoints => [for (final ip in _lanIps) '$ip:47800'];

  /// Starts discovery, the pairing listener and the sync/overflow
  /// servers — automatically, invisibly, the way the owner expects
  /// "networking" to behave. Each piece fails soft: a taken port or a
  /// missing network must never break the screen.
  Future<void> _startNetworkServices() async {
    final identity = _identity;
    if (identity == null || !_visible) return;
    // Sync server (answers paired peers that initiate).
    if (_server == null) {
      final server = SyncServer();
      try {
        await server.start(
          local: identity,
          allowedPeers: _paired,
          loadRecords: () => _coordinator().buildRecords(),
          onSync: (result) async {
            final report = await _coordinator().applyResult(result);
            if (!mounted) return;
            _showStatus(S.of(context).dIncomingSync(
                report.projectsApplied, report.conflictsCreated, report.deleted));
            await _reloadTrash();
          },
        );
        _server = server;
        if (mounted) setState(() => _syncServerOn = true);
      } catch (_) {
        // Port busy etc. — auto-sync (initiator side) still works.
      }
    }
    // Overflow server (executes shared tools for paired peers).
    if (_overflowServer == null) {
      try {
        await _startOverflowServer();
      } catch (_) {}
    }
    // Pairing listener (in-network pairing requests).
    if (_pairingServer == null) {
      final server = LanPairingServer();
      try {
        await server.start(
          local: identity,
          displayName: _displayName,
          localEndpoints: () => _myEndpoints,
          onIncoming: (incoming) {
            if (mounted) setState(() => _incoming = incoming);
          },
          onPaired: (paired) async {
            await PairedDevicesStore(widget.baseDir).add(paired);
            await _reloadPaired();
            await _restartServers();
            if (mounted) _showStatus(S.of(context).dPaired);
          },
        );
        _pairingServer = server;
      } catch (_) {}
    }
    // Discovery.
    if (_discovery == null) {
      final discovery = PeerDiscovery(
        deviceId: identity.deviceId,
        displayName: _displayName,
      );
      _discovery = discovery;
      _discoverySub = discovery.onPeersChanged.listen((peers) {
        if (!mounted) return;
        setState(() => _nearby = peers);
        _adoptDiscoveredEndpoints(peers);
      });
      try {
        await discovery.start();
        discovery.probe();
      } catch (_) {}
    }
  }

  Future<void> _startOverflowServer() async {
    final server = OverflowServer();
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
          return OverflowToolReply(ok: false, output: 'unknown tool: $toolId');
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
    if (mounted) setState(() => _overflowOn = true);
  }

  Future<void> _stopNetworkServices() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _discovery?.close();
    _discovery = null;
    await _pairingServer?.close();
    _pairingServer = null;
    await _server?.close();
    _server = null;
    await _overflowServer?.close();
    _overflowServer = null;
    if (mounted) {
      setState(() {
        _syncServerOn = false;
        _overflowOn = false;
        _nearby = const [];
      });
    }
  }

  /// Servers capture the paired list at start; after pairing changes,
  /// restart them so the new peer is authorized immediately.
  Future<void> _restartServers() async {
    await _server?.close();
    _server = null;
    await _overflowServer?.close();
    _overflowServer = null;
    if (mounted) {
      setState(() {
        _syncServerOn = false;
        _overflowOn = false;
      });
    }
    await _startNetworkServices();
  }

  /// A paired device seen at a new address gets its stored endpoint
  /// updated automatically — DHCP changes stop breaking sync.
  Future<void> _adoptDiscoveredEndpoints(List<DiscoveredPeer> peers) async {
    final store = PairedDevicesStore(widget.baseDir);
    var changed = false;
    for (final peer in peers) {
      final match =
          _paired.where((p) => p.identity.deviceId == peer.deviceId);
      if (match.isEmpty) continue;
      final current = match.first;
      if (current.endpoints.isEmpty ||
          current.endpoints.first != peer.syncEndpoint) {
        await store.add(PairedDevice(
          identity: current.identity,
          pairedAtIso: current.pairedAtIso,
          endpoints: [peer.syncEndpoint],
        ));
        changed = true;
      }
    }
    if (changed) await _reloadPaired();
  }

  Future<void> _reloadPaired() async {
    final paired = await PairedDevicesStore(widget.baseDir).list();
    if (mounted) setState(() => _paired = paired);
  }

  Future<void> _reloadTrash() async {
    if (_identity == null) return;
    final trash = await _coordinator().trash();
    if (mounted) setState(() => _trashCount = trash.length);
  }

  void _showStatus(String message) {
    if (mounted) setState(() => _status = message);
  }

  // ---- LAN pairing (outgoing) ----

  Future<void> _pairWith(DiscoveredPeer peer) async {
    final s = S.of(context);
    setState(() => _pairingOut = true);
    try {
      final paired = await LanPairingClient.pair(
        host: peer.ip,
        local: _identity!,
        displayName: _displayName,
        localEndpoints: _myEndpoints,
        confirmSas: (sas, peerName) async {
          if (!mounted) return false;
          final ok = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Text(s.pairingSasTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.pairingSasBody(peerName, sas)),
                  const SizedBox(height: CairnSpacing.md),
                  Text(sas,
                      style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(s.reject),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(s.accept),
                ),
              ],
            ),
          );
          return ok ?? false;
        },
      );
      await PairedDevicesStore(widget.baseDir).add(paired);
      await _reloadPaired();
      await _restartServers();
      _showStatus(s.dPaired);
    } on PairingRejectedException {
      _showStatus(s.pairingRejected);
    } catch (e) {
      _showStatus(s.pairingFailed('$e'));
    }
    if (mounted) setState(() => _pairingOut = false);
  }

  // ---- sync / capabilities (unchanged flows) ----

  Future<void> _syncNow(PairedDevice peer) async {
    final s = S.of(context);
    final host = _hostControllers[peer.identity.deviceId]?.text.trim() ??
        (peer.endpoints.isEmpty ? '' : peer.endpoints.first.split(':').first);
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
      _showStatus(s.dSyncDone(report.projectsApplied, report.skillsApplied,
          report.conflictsCreated, report.deleted));
    } catch (e) {
      _showStatus(s.dSyncFailed('$e'));
    }
  }

  Future<void> _showPeerCapabilities(PairedDevice peer) async {
    final s = S.of(context);
    final host = _hostControllers[peer.identity.deviceId]?.text.trim() ??
        (peer.endpoints.isEmpty ? '' : peer.endpoints.first.split(':').first);
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
      _showStatus(s.dCapsLine(
          peer.identity.displayName,
          caps.cpuCores,
          caps.ramMb,
          caps.hasGpu ? s.dHas : s.dHasNot,
          verdict(heavyRam),
          verdict(gpuStep)));
    } catch (e) {
      _showStatus(s.dCapsFailed('$e'));
    }
  }

  // ---- legacy manual pairing ----

  Future<void> _makeOffer() async {
    final identity = _identity!;
    final offer = PairingOffer(
      identity: DeviceIdentity(
        deviceId: identity.deviceId,
        publicKeyBytes: identity.publicKeyBytes,
        displayName: _displayName,
      ),
      nonce: secureRandomBytes(16),
      endpoints: _myEndpoints,
    );
    setState(() => _offerText = offer.encode());
  }

  Future<void> _inspectOffer() async {
    final s = S.of(context);
    try {
      final offer = PairingOffer.decode(_pasteController.text.trim());
      final session =
          await PairingSession.fromOffer(local: _identity!, offer: offer);
      setState(() => _pendingSession = session);
    } on FormatException catch (e) {
      _showStatus(s.dInvalidOffer(e.message));
    }
  }

  Future<void> _confirmPairing() async {
    final session = _pendingSession;
    if (session == null) return;
    await PairedDevicesStore(widget.baseDir).add(session.confirm());
    await _reloadPaired();
    await _restartServers();
    setState(() {
      _pendingSession = null;
      _pasteController.clear();
    });
    if (mounted) _showStatus(S.of(context).dPaired);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final identity = _identity;
    if (identity == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final onLan = _lanIps.isNotEmpty;
    final pairedIds = {for (final p in _paired) p.identity.deviceId};
    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(CairnSpacing.lg),
      children: [
        // ---- Network status: the answer to "am I even connected?" ----
        Text(s.netTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(CairnSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      onLan
                          ? Icons.wifi
                          : (_lanState == LanState.cellularOnly
                              ? Icons.signal_cellular_alt
                              : Icons.wifi_off),
                      color: onLan
                          ? Colors.green
                          : (_lanState == LanState.cellularOnly
                              ? Colors.orange
                              : theme.colorScheme.error),
                    ),
                    const SizedBox(width: CairnSpacing.sm),
                    Expanded(
                      child: Text(onLan
                          ? s.netConnected
                          : (_lanState == LanState.cellularOnly
                              ? s.netCellularOnly
                              : s.netOffline)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        await _refreshNetwork();
                        _discovery?.probe();
                      },
                    ),
                  ],
                ),
                if (onLan) ...[
                  const SizedBox(height: CairnSpacing.xs),
                  SelectableText(s.netYourAddress(_lanIps.first)),
                  const SizedBox(height: CairnSpacing.xs),
                  Text(
                    _syncServerOn && _overflowOn
                        ? s.netServersOn
                        : '…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.netVisible),
                  subtitle: Text(s.netVisibleSub),
                  value: _visible,
                  onChanged: (v) async {
                    setState(() => _visible = v);
                    if (v) {
                      await _startNetworkServices();
                    } else {
                      await _stopNetworkServices();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        // ---- Incoming pairing request ----
        if (_incoming != null) ...[
          const SizedBox(height: CairnSpacing.md),
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(CairnSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.pairingIncoming(_incoming!.peerName),
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: CairnSpacing.xs),
                  Text(s.pairingSasBody(_incoming!.peerName, _incoming!.sas)),
                  Text(_incoming!.sas,
                      style: theme.textTheme.headlineMedium),
                  const SizedBox(height: CairnSpacing.sm),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () {
                          _incoming!.accept();
                          setState(() => _incoming = null);
                        },
                        child: Text(s.accept),
                      ),
                      const SizedBox(width: CairnSpacing.sm),
                      OutlinedButton(
                        onPressed: () {
                          _incoming!.reject();
                          setState(() => _incoming = null);
                        },
                        child: Text(s.reject),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: CairnSpacing.xxl),
        // ---- Nearby devices (discovery) ----
        Text(s.nearbyTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: CairnSpacing.sm),
        if (_nearby.isEmpty)
          Text(s.nearbyNone)
        else
          for (final peer in _nearby)
            Card(
              child: ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(peer.displayName.isEmpty
                    ? peer.deviceId
                    : peer.displayName),
                subtitle: Text(peer.ip),
                trailing: pairedIds.contains(peer.deviceId)
                    ? Chip(label: Text(s.pairedBadge))
                    : FilledButton(
                        onPressed:
                            _pairingOut ? null : () => _pairWith(peer),
                        child: Text(s.pairAction),
                      ),
              ),
            ),
        const Divider(height: CairnSpacing.xxl),
        // ---- This device ----
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
                setState(() => _displayName = _nameController.text.trim());
                _discovery?.displayName = _displayName;
              },
              child: Text(s.dSave),
            ),
          ],
        ),
        const Divider(height: CairnSpacing.xxl),
        // ---- Paired devices ----
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
                    Text(peer.identity.displayName.isEmpty
                        ? peer.identity.deviceId
                        : peer.identity.displayName),
                    Text(peer.identity.deviceId,
                        style: theme.textTheme.bodySmall),
                    if (peer.endpoints.isNotEmpty)
                      Text(peer.endpoints.first,
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
                                    : peer.endpoints.first.split(':').first,
                              ),
                            ),
                            decoration:
                                InputDecoration(labelText: s.dHostLabel),
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
                            await _reloadPaired();
                            await _restartServers();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        const Divider(height: CairnSpacing.xxl),
        // ---- Overflow specs ----
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
          onChanged: (v) => setState(() => _hasGpu = v),
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
          title: Text(s.dRemoteSensitiveTitle),
          subtitle: Text(s.dRemoteSensitiveSub),
          value: _overflowSensitive,
          onChanged: (v) async {
            setState(() => _overflowSensitive = v);
            await _restartServers();
          },
        ),
        if (_trashCount > 0) Text(s.dTrashLine(_trashCount)),
        const Divider(height: CairnSpacing.xxl),
        // ---- Legacy manual pairing ----
        ExpansionTile(
          title: Text(s.manualPairTitle),
          children: [
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
              Text(s.dSasLabel, style: theme.textTheme.bodyMedium),
              Text(_pendingSession!.sas,
                  style: theme.textTheme.headlineMedium),
              FilledButton(
                onPressed: _confirmPairing,
                child: Text(s.dPairConfirm),
              ),
            ],
          ],
        ),
        if (_status.isNotEmpty) ...[
          const SizedBox(height: CairnSpacing.md),
          Text(_status),
        ],
      ],
    );
  }
}
