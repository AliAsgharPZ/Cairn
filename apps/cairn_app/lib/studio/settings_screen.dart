import 'dart:io';
import 'package:cairn_core/cairn_core.dart';
import 'package:cairn_models/cairn_models.dart';
import 'package:cairn_runtime/cairn_runtime.dart';
import 'package:cairn_training/cairn_training.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../ui/strings.dart';
import '../ui/tokens.dart';
import 'app_settings.dart';
import 'backup_service.dart';
import 'device_identity.dart';
import 'language_store.dart';
import 'devices_screen.dart';
import 'project_store.dart';
import 'provider_factory.dart';
import 'provider_settings.dart';
import 'skill_store.dart';

/// Provider management: configure model providers (adapter, base URL,
/// default model), store API keys in the platform secure store, and test
/// the connection with a real minimal completion call.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsStore,
    required this.keyStore,
    this.onChanged,
    this.modelRegistry,
    this.appSettings,
    this.onAppSettingsChanged,
    this.projectsStore,
    this.skillStore,
    this.seedStore,
    this.toolRegistry,
  });

  final ProviderSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final VoidCallback? onChanged;

  /// App-level settings (language/theme) for the appearance section.
  final AppSettings? appSettings;
  final ValueChanged<AppSettings>? onAppSettingsChanged;

  /// Stores for the embedded «دستگاه‌ها و سینک» section (the Devices
  /// screen moved into Settings per the owner's request). All four
  /// are required for the section to appear.
  final ProjectStore? projectsStore;
  final SkillStore? skillStore;
  final SeedStore? seedStore;
  final ToolRegistry? toolRegistry;

  /// Registry of locally trained models (for 'local-trained' configs).
  final ModelRegistryStore? modelRegistry;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<ProviderConfig> _configs = const [];
  final Map<String, bool> _hasKey = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final configs = await widget.settingsStore.load();
    final keyStatus = <String, bool>{};
    for (final c in configs) {
      keyStatus[c.providerId] =
          (await widget.keyStore.read(c.providerId)) != null;
    }
    if (mounted) {
      setState(() {
        _configs = configs;
        _hasKey
          ..clear()
          ..addAll(keyStatus);
        _loading = false;
      });
    }
  }

  Future<void> _edit(ProviderConfig? existing) async {
    final providerId =
        existing?.providerId ??
        knownProviders.keys.firstWhere(
          (id) => !_configs.any((c) => c.providerId == id),
          orElse: () => knownProviders.keys.first,
        );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProviderDialog(
        settingsStore: widget.settingsStore,
        keyStore: widget.keyStore,
        existing: existing,
        initialProviderId: providerId,
        hasKey: _hasKey[providerId] ?? false,
      ),
    );
    if (saved == true) {
      await _reload();
      widget.onChanged?.call();
    }
  }

  Future<void> _delete(ProviderConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف ارائه‌دهنده'),
        content: Text(
          'پیکربندی «${knownProviders[config.providerId] ?? config.providerId}» و کلیدش حذف شود؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.settingsStore.remove(config.providerId);
    await widget.keyStore.delete(config.providerId);
    await _reload();
    widget.onChanged?.call();
  }

  Future<void> _testConnection(ProviderConfig config) async {
    if (config.defaultModelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('برای تست اتصال، اول «مدل پیش‌فرض» را پر کن'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('در حال تست اتصال…')));
    try {
      final provider = buildProvider(
        config,
        widget.keyStore,
        modelRegistry: widget.modelRegistry,
      );
      final res = await provider
          .complete(
            ModelConfig(
              providerId: config.providerId,
              modelId: config.defaultModelId,
            ),
            const ModelRequest(
              messages: [ChatMessage(ChatRole.user, 'Reply with exactly: OK')],
              maxOutputTokens: 8,
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'اتصال موفق بود. پاسخ مدل: ${res.text.trim().isEmpty ? '(خالی)' : res.text.trim()}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطای اتصال: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final appSettings = widget.appSettings;
    return ListView(
      padding: const EdgeInsets.all(CairnSpacing.md),
      children: [
        if (appSettings != null) ...[
          Text(s.appearanceAndLanguage, style: theme.textTheme.headlineMedium),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: CairnSpacing.xs),
            color: CairnColors.accentGold,
          ),
          const SizedBox(height: CairnSpacing.md),
          Text(s.language, style: theme.textTheme.labelLarge),
          const SizedBox(height: CairnSpacing.xs),
          Wrap(
            spacing: CairnSpacing.sm,
            children: [
              ChoiceChip(
                label: Text(s.persian),
                selected: appSettings.languageCode == 'fa',
                onSelected: (sel) {
                  if (sel) {
                    widget.onAppSettingsChanged?.call(
                      appSettings.copyWith(languageCode: 'fa'),
                    );
                  }
                },
              ),
              ChoiceChip(
                label: Text(s.english),
                selected: appSettings.languageCode == 'en',
                onSelected: (sel) {
                  if (sel) {
                    widget.onAppSettingsChanged?.call(
                      appSettings.copyWith(languageCode: 'en'),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: CairnSpacing.md),
          Text(s.theme, style: theme.textTheme.labelLarge),
          const SizedBox(height: CairnSpacing.xs),
          Wrap(
            spacing: CairnSpacing.sm,
            children: [
              for (final (value, label) in [
                ('system', s.themeSystem),
                ('light', s.themeLight),
                ('dark', s.themeDark),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: appSettings.themeMode == value,
                  onSelected: (sel) {
                    if (sel) {
                      widget.onAppSettingsChanged?.call(
                        appSettings.copyWith(themeMode: value),
                      );
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: CairnSpacing.xxl),
        ],
        if (widget.projectsStore != null) ...[
          Text(s.myLanguages, style: theme.textTheme.headlineMedium),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: CairnSpacing.xs),
            color: CairnColors.accentGold,
          ),
          const SizedBox(height: CairnSpacing.sm),
          Text(s.myLanguagesHelp, style: theme.textTheme.bodySmall),
          const SizedBox(height: CairnSpacing.sm),
          _LanguagesCard(baseDir: widget.projectsStore!.baseDir),
          const SizedBox(height: CairnSpacing.xxl),
        ],
        if (widget.projectsStore != null) ...[
          Text(s.backupTitle, style: theme.textTheme.headlineMedium),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: CairnSpacing.xs),
            color: CairnColors.accentGold,
          ),
          const SizedBox(height: CairnSpacing.sm),
          Text(s.backupHelp, style: theme.textTheme.bodySmall),
          const SizedBox(height: CairnSpacing.sm),
          Wrap(
            spacing: CairnSpacing.sm,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.save_alt_outlined),
                label: Text(s.backupExport),
                onPressed: () async {
                  final location = await getSaveLocation(
                    suggestedName: 'cairn-backup.zip',
                    acceptedTypeGroups: const [
                      XTypeGroup(label: 'ZIP', extensions: ['zip']),
                    ],
                  );
                  if (location == null) return;
                  await BackupService(widget.projectsStore!.baseDir)
                      .exportTo(location.path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.backupDone)));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.restore_outlined),
                label: Text(s.backupImport),
                onPressed: () async {
                  final file = await openFile(
                    acceptedTypeGroups: const [
                      XTypeGroup(label: 'ZIP', extensions: ['zip']),
                    ],
                  );
                  if (file == null || !context.mounted) return;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(s.backupImport),
                      content: Text(s.backupHelp),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(s.cReject),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(s.backupImport),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  final count = await BackupService(
                          widget.projectsStore!.baseDir)
                      .importFrom(file.path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('${s.backupDone} ($count)')));
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: CairnSpacing.xxl),
        ],
        if (widget.projectsStore != null &&
            widget.skillStore != null &&
            widget.seedStore != null &&
            widget.toolRegistry != null) ...[
          Text(s.devicesAndSync, style: theme.textTheme.headlineMedium),
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: CairnSpacing.xs),
            color: CairnColors.accentGold,
          ),
          DevicesScreen(
            embedded: true,
            projects: widget.projectsStore!,
            skills: widget.skillStore!,
            baseDir: widget.projectsStore!.baseDir,
            seedStore: widget.seedStore!,
            registry: widget.toolRegistry!,
          ),
          const SizedBox(height: CairnSpacing.xxl),
        ],
        Row(
          children: [
            Text('ارائه‌دهنده‌های مدل', style: theme.textTheme.headlineMedium),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add),
              label: const Text('افزودن ارائه‌دهنده'),
            ),
          ],
        ),
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: CairnSpacing.xs),
          color: CairnColors.accentGold,
        ),
        const SizedBox(height: CairnSpacing.md),
        Text(
          'کلیدهای API در حافظهٔ امن سیستم‌عامل (Keystore / DPAPI) نگه‌داری می‌شوند؛ '
          'هرگز داخل فایل پروژه یا تنظیمات ذخیره نمی‌شوند.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: CairnSpacing.xxl),
        if (_loading)
          const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_configs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CairnSpacing.lg),
            child: Text(
              'هنوز ارائه‌دهنده‌ای پیکربندی نشده. برای اجرای ایجنت‌ها یکی اضافه کن (مثلاً Ollama محلی یا یک API).',
            ),
          )
        else
          for (final c in _configs) ...[
            _providerCard(c),
            const SizedBox(height: CairnSpacing.sm),
          ],
      ],
    );
  }

  Widget _providerCard(ProviderConfig c) {
    final needsKey = c.providerId != 'ollama';
    return Card(
      child: ListTile(
        title: Text(knownProviders[c.providerId] ?? c.providerId),
        subtitle: Text(
          [
            if (c.baseUrl != null) c.baseUrl!,
            if (c.defaultModelId.isNotEmpty) 'مدل پیش‌فرض: ${c.defaultModelId}',
            if (needsKey)
              (_hasKey[c.providerId] ?? false)
                  ? 'کلید API: ذخیره شده'
                  : 'کلید API: تنظیم نشده',
          ].join(' · '),
        ),
        trailing: Wrap(
          spacing: CairnSpacing.xs,
          children: [
            IconButton(
              icon: const Icon(Icons.wifi_tethering),
              tooltip: 'تست اتصال',
              onPressed: () => _testConnection(c),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'ویرایش',
              onPressed: () => _edit(c),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'حذف',
              onPressed: () => _delete(c),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderDialog extends StatefulWidget {
  const _ProviderDialog({
    required this.settingsStore,
    required this.keyStore,
    required this.existing,
    required this.initialProviderId,
    required this.hasKey,
  });

  final ProviderSettingsStore settingsStore;
  final ApiKeyStore keyStore;
  final ProviderConfig? existing;
  final String initialProviderId;
  final bool hasKey;

  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  late String _providerId = widget.initialProviderId;
  late final _baseUrl = TextEditingController(text: widget.existing?.baseUrl);
  late final _modelId = TextEditingController(
    text: widget.existing?.defaultModelId,
  );
  final _apiKey = TextEditingController();

  @override
  void dispose() {
    _baseUrl.dispose();
    _modelId.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.settingsStore.upsert(
      ProviderConfig(
        providerId: _providerId,
        baseUrl: _baseUrl.text.trim().isEmpty ? null : _baseUrl.text.trim(),
        defaultModelId: _modelId.text.trim(),
      ),
    );
    if (_apiKey.text.isNotEmpty) {
      await widget.keyStore.write(_providerId, _apiKey.text);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'افزودن ارائه‌دهنده' : 'ویرایش ارائه‌دهنده'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _providerId,
              decoration: const InputDecoration(labelText: 'نوع ارائه‌دهنده'),
              items: [
                for (final e in knownProviders.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: isNew
                  ? (v) => setState(() => _providerId = v ?? _providerId)
                  : null,
            ),
            const SizedBox(height: CairnSpacing.sm),
            TextField(
              controller: _baseUrl,
              decoration: const InputDecoration(
                labelText: 'آدرس پایه (Base URL) — اختیاری',
                hintText: 'https://api.openai.com/v1',
              ),
            ),
            const SizedBox(height: CairnSpacing.sm),
            TextField(
              controller: _modelId,
              decoration: const InputDecoration(
                labelText: 'مدل پیش‌فرض',
                hintText: 'gpt-4o-mini / llama3.1 / …',
              ),
            ),
            if (_providerId != 'ollama') ...[
              const SizedBox(height: CairnSpacing.sm),
              TextField(
                controller: _apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.hasKey
                      ? 'کلید API (خالی = بدون تغییر)'
                      : 'کلید API',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('لغو'),
        ),
        FilledButton(onPressed: _save, child: const Text('ذخیره')),
      ],
    );
  }
}

/// The language registry card (v1.4): built-in languages are listed
/// and locked; the owner can add ANY custom language (name, English
/// name for model prompts, code, direction) or remove their own.
class _LanguagesCard extends StatefulWidget {
  const _LanguagesCard({required this.baseDir});

  final Directory baseDir;

  @override
  State<_LanguagesCard> createState() => _LanguagesCardState();
}

class _LanguagesCardState extends State<_LanguagesCard> {
  List<AppLanguage> _languages = const [];
  late final LanguageStore _store = LanguageStore(widget.baseDir);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final langs = await _store.list();
    if (mounted) setState(() => _languages = langs);
  }

  Future<void> _add() async {
    final s = S.of(context);
    final name = TextEditingController();
    final english = TextEditingController();
    final code = TextEditingController();
    var rtl = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(s.addLanguage),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: s.langDisplayName),
                ),
                TextField(
                  controller: english,
                  decoration: InputDecoration(labelText: s.langEnglishName),
                ),
                TextField(
                  controller: code,
                  decoration: InputDecoration(labelText: s.langCode),
                ),
                SwitchListTile(
                  title: Text(s.langRtl),
                  value: rtl,
                  onChanged: (v) => setLocal(() => rtl = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cReject),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.addLanguage),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final c = code.text.trim().toLowerCase();
    if (c.isEmpty || name.text.trim().isEmpty) return;
    await _store.add(AppLanguage(
      code: c,
      name: name.text.trim(),
      englishName:
          english.text.trim().isEmpty ? c : english.text.trim(),
      rtl: rtl,
    ));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in _languages)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(l.name),
            subtitle: Text('${l.code} · ${l.englishName}'),
            trailing: l.builtin
                ? Chip(label: Text(s.builtinLang))
                : IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await _store.remove(l.code);
                      await _reload();
                    },
                  ),
          ),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: Text(s.addLanguage),
        ),
      ],
    );
  }
}
