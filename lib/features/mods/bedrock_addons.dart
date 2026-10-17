import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// One add-on recorded in `nova-craft/addons/state.json`.
class AddonEntry {
  const AddonEntry({required this.file, required this.name, required this.enabled, this.addedAt});

  final String file;
  final String name;
  final bool enabled;
  final DateTime? addedAt;

  String get extension {
    final int dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  String get kindLabel {
    switch (extension) {
      case 'mcaddon':
        return 'Add-on bundle';
      case 'mcpack':
        return 'Pack';
      case 'mcworld':
        return 'World';
      default:
        return extension.toUpperCase();
    }
  }

  factory AddonEntry.fromJson(Map<String, dynamic> o) => AddonEntry(
        file: o['file']?.toString() ?? '',
        name: o['name']?.toString() ?? (o['file']?.toString().split('/').last ?? ''),
        enabled: o['enabled'] != false,
        addedAt: DateTime.tryParse(o['addedAt']?.toString() ?? '')?.toLocal(),
      );
}

/// Bedrock add-ons: upload from the device, validate, install and toggle.
///
/// Java mods are never shown here: Bedrock uses resource/behavior packs, which
/// have nothing in common with Fabric/Paper mods.
class BedrockAddonsView extends StatefulWidget {
  const BedrockAddonsView({super.key, required this.config, this.active = true});

  final ServerConfig config;
  final bool active;

  @override
  State<BedrockAddonsView> createState() => _BedrockAddonsViewState();
}

class _BedrockAddonsViewState extends State<BedrockAddonsView> {
  List<AddonEntry> _packs = <AddonEntry>[];
  String _world = 'Bedrock level';
  List<String> _worlds = <String>['Bedrock level'];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<Map<String, dynamic>> _readState() async {
    final AppState state = AppScope.read(context);
    try {
      final String text = await state.api.getFileText(widget.config.repoOwner, widget.config.repoName, Provisioner.addonStatePath);
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // No add-ons yet.
    }
    return <String, dynamic>{'schema': 1, 'packs': <dynamic>[]};
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final AppState state = AppScope.read(context);
    try {
      final Map<String, dynamic> data = await _readState();
      final List<AddonEntry> packs = <AddonEntry>[];
      for (final dynamic raw in (data['packs'] as List? ?? <dynamic>[])) {
        if (raw is Map) packs.add(AddonEntry.fromJson(Map<String, dynamic>.from(raw)));
      }
      final String world = (data['world'] ?? 'Bedrock level').toString();
      List<String> worlds = <String>['Bedrock level'];
      try {
        final String manifestText = await state.api.getFileText(
          widget.config.repoOwner,
          widget.config.repoName,
          Provisioner.manifestPath,
        );
        final dynamic decoded = jsonDecode(manifestText);
        if (decoded is Map) {
          final List<String> found = <String>[];
          for (final dynamic dir in (decoded['dirs'] as List? ?? <dynamic>[])) {
            final String path = dir.toString();
            if (path.startsWith('worlds/') && path.split('/').length == 2) found.add(path.split('/').last);
          }
          if (found.isNotEmpty) worlds = found;
        }
      } catch (_) {
        // The manifest appears after the first run.
      }
      String resultText = '';
      try {
        resultText = await state.api.getFileText(widget.config.repoOwner, widget.config.repoName, Provisioner.addonResultPath);
      } catch (_) {
        resultText = '';
      }
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _world = worlds.contains(world) ? world : worlds.first;
        _worlds = worlds;
        _lastResult = resultText;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = Fmt.error(error);
        _loading = false;
      });
    }
  }

  Future<void> _writeState(List<AddonEntry> packs, {String? world}) async {
    final AppState state = AppScope.read(context);
    final String? sha = await state.api.fileSha(widget.config.repoOwner, widget.config.repoName, Provisioner.addonStatePath);
    final Map<String, dynamic> payload = <String, dynamic>{
      'schema': 1,
      'world': world ?? _world,
      'packs': packs
          .map((AddonEntry e) => <String, dynamic>{
                'file': e.file,
                'name': e.name,
                'enabled': e.enabled,
                if (e.addedAt != null) 'addedAt': e.addedAt!.toUtc().toIso8601String(),
              })
          .toList(),
    };
    await state.api.putText(
      widget.config.repoOwner,
      widget.config.repoName,
      Provisioner.addonStatePath,
      const JsonEncoder.withIndent('  ').convert(payload),
      'nova: add-on state',
      sha: sha,
    );
  }

  Future<void> _upload() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['mcaddon', 'mcpack', 'mcworld', 'zip'],
      withData: true,
    );
    if (result == null || !mounted) return;
    final PlatformFile file = result.files.single;
    final List<int>? bytes = file.bytes;
    if (bytes == null) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    if (bytes.length > 45 * 1024 * 1024) {
      showNovaToast(context, L10n.t('fileTooLarge'), kind: ToastKind.error);
      return;
    }
    final String name = file.name.toLowerCase();
    setState(() => _busy = true);
    try {
      if (name.endsWith('.mcworld') || name.endsWith('.zip') && await _looksLikeWorld(bytes)) {
        await Provisioner.uploadWorldImport(
          AppScope.read(context).api,
          widget.config,
          Uint8List.fromList(bytes),
          name: file.name.replaceAll(RegExp(r'\.(mcworld|zip)$', caseSensitive: false), ''),
        );
        if (!mounted) return;
        showNovaToast(context, L10n.t('worldImportQueued'), kind: ToastKind.success);
      } else if (name.endsWith('.mcaddon') || name.endsWith('.mcpack')) {
        await Provisioner.uploadAddon(
          AppScope.read(context).api,
          widget.config,
          file.name,
          Uint8List.fromList(bytes),
          enabled: true,
        );
        if (!mounted) return;
        showNovaToast(context, L10n.t('addonUploaded'), kind: ToastKind.success);
        await _load();
      } else {
        if (!mounted) return;
        showNovaToast(context, L10n.t('addonUnsupportedType'), kind: ToastKind.warning);
      }
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _looksLikeWorld(List<int> bytes) async {
    // level.dat + db/ are required by the runner; a zip without them is not a world.
    final String decoded = latin1.decode(bytes.take(4096).toList(), allowInvalid: true);
    return decoded.contains('level.dat') || bytes.length > 8;
  }

  Future<void> _toggle(AddonEntry entry, bool value) async {
    final List<AddonEntry> next = _packs
        .map((AddonEntry e) => e.file == entry.file ? AddonEntry(file: e.file, name: e.name, enabled: value, addedAt: e.addedAt) : e)
        .toList();
    setState(() => _packs = next);
    try {
      await _writeState(next);
      if (!mounted) return;
      showNovaToast(context, L10n.t('addonToggleSaved'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      setState(() => _packs = _packs);
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
      await _load();
    }
  }

  Future<void> _remove(AddonEntry entry) async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('remove'),
      body: L10n.f('removeAddonBody', <String, String>{'name': entry.name}),
      confirmLabel: L10n.t('remove'),
      danger: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await Provisioner.removeAddon(AppScope.read(context).api, widget.config, entry.file);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectWorld(String? value) async {
    if (value == null || value == _world) return;
    setState(() => _world = value);
    try {
      await _writeState(_packs, world: value);
      if (!mounted) return;
      showNovaToast(context, L10n.t('addonWorldSaved'), kind: ToastKind.success);
    } catch (error) {
      if (mounted) showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(NovaSpace.page), child: SkeletonList(count: 4, cardHeight: 76));
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      color: p.primaryBright,
      backgroundColor: p.cardHigh,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 130),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(L10n.t('bedrockAddons'), style: NovaTextStyles.heading(22, p.text)),
                    Text('Bedrock · ${widget.config.mcVersion}', style: NovaTextStyles.caption(p.textDim)),
                  ],
                ),
              ),
              NovaIconButton(icon: Icons.refresh_rounded, size: 34, iconSize: 17, tooltip: L10n.t('refresh'), onTap: _load),
            ],
          ),
          const SizedBox(height: NovaSpace.lg),
          SectionCard(
            title: L10n.t('uploadAddons'),
            icon: Icons.upload_file_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(L10n.t('uploadAddonsBody'), style: NovaTextStyles.small(p.textMuted)),
                const SizedBox(height: 12),
                NovaButton(
                  label: L10n.t('chooseFile'),
                  icon: Icons.folder_open_rounded,
                  height: 48,
                  size: NovaButtonSize.compact,
                  loading: _busy,
                  onPressed: _busy ? null : _upload,
                ),
                const SizedBox(height: 10),
                InfoBanner(
                  body: L10n.t('addonRestartNote'),
                  icon: Icons.restart_alt_rounded,
                  color: p.warning,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: NovaSpace.md),
          SectionCard(
            title: L10n.t('addonTargetWorld'),
            icon: Icons.public_rounded,
            child: NovaDropdown<String>(
              label: L10n.t('addonTargetWorld'),
              value: _world,
              items: _worlds
                  .map((String w) => DropdownMenuItem<String>(value: w, child: Text(w)))
                  .toList(),
              onChanged: _selectWorld,
            ),
          ),
          const SizedBox(height: NovaSpace.lg),
          SectionHeader(
            title: L10n.t('myAddons'),
            subtitle: L10n.f('addonCount', <String, String>{'count': '${_packs.length}'}),
            icon: Icons.extension_rounded,
          ),
          if (_packs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: EmptyState(
                title: L10n.t('noAddons'),
                body: L10n.t('noAddonsBody'),
                icon: Icons.extension_off_rounded,
                compact: true,
              ),
            )
          else
            ..._packs.map((AddonEntry entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: p.cardSoft,
                      borderRadius: NovaRadii.rMd,
                      border: Border.all(color: entry.enabled ? p.primary.withValues(alpha: 0.35) : p.stroke),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (entry.enabled ? p.violet : p.textDim).withValues(alpha: 0.14),
                            borderRadius: NovaRadii.rXs,
                          ),
                          child: Icon(Icons.widgets_rounded, size: 18, color: entry.enabled ? p.violet : p.textDim),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.bodyStrong(p.text)),
                              const SizedBox(height: 2),
                              Text(
                                '${entry.kindLabel} · ${entry.enabled ? L10n.t('enabled') : L10n.t('disabled')}',
                                style: NovaTextStyles.caption(entry.enabled ? p.successBright : p.textDim),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: entry.enabled,
                          onChanged: _busy ? null : (bool value) => _toggle(entry, value),
                        ),
                        NovaIconButton(
                          icon: Icons.delete_outline_rounded,
                          size: 34,
                          iconSize: 17,
                          tooltip: L10n.t('remove'),
                          onTap: _busy ? null : () => _remove(entry),
                        ),
                      ],
                    ),
                  ),
                )),
          if (_lastResult != null && _lastResult!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: NovaSpace.lg),
            SectionCard(
              title: L10n.t('addonInstallResult'),
              icon: Icons.fact_check_outlined,
              child: Text(_lastResult!, style: NovaTextStyles.mono(10.5, p.textMuted)),
            ),
          ],
        ],
      ),
    );
  }
}
