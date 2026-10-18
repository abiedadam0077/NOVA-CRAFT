import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import 'device_flow_card.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, this.showBack = true});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              NovaTopBar(
                onBack: showBack ? () => Navigator.of(context).maybePop() : null,
                showBrand: true,
                title: null,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 40),
                  children: <Widget>[
                    ArtBanner(
                      asset: 'assets/images/art_island.jpg',
                      height: 168,
                      alignment: Alignment.center,
                      radius: NovaRadii.rXl,
                    ),
                    const SizedBox(height: 22),
                    Text(L10n.t('signInTitle'), style: NovaTextStyles.display(26, p.text)),
                    const SizedBox(height: 8),
                    Text(L10n.t('signInSubtitle'), style: NovaTextStyles.body(p.textMuted)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.cardSoft,
                        borderRadius: NovaRadii.rLg,
                        border: Border.all(color: p.stroke),
                      ),
                      child: Column(
                        children: <Widget>[
                          PermissionRow(label: L10n.t('permissionRepos')),
                          PermissionRow(label: L10n.t('permissionActions')),
                          PermissionRow(label: L10n.t('permissionServers')),
                          PermissionRow(label: L10n.t('permissionSecurity')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    DeviceFlowCard(
                      onAuthorized: (String access, String? refresh, int? expiresIn) async {
                        await state.completeLogin(access, refresh, expiresIn);
                      },
                    ),
                    if (state.sessionExpired) ...<Widget>[
                      const SizedBox(height: 14),
                      InfoBanner(
                        body: L10n.t('errorUnauthorized'),
                        icon: Icons.lock_clock_rounded,
                        color: p.warning,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: <Widget>[
                        Icon(Icons.lock_rounded, size: 14, color: p.textDim),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            L10n.t('privacyBody'),
                            style: NovaTextStyles.small(p.textDim),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Center(child: BrandWordmark(fontSize: 11, letterSpacing: 3, color: p.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
