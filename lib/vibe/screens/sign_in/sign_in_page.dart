// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:vibe/config/themes.dart';
import 'package:vibe/vibe/screens/sign_in/view_model/model/public_homeserver_data.dart';
import 'package:vibe/vibe/screens/sign_in/view_model/sign_in_view_model.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/utils/sign_in_flows/check_homeserver.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/widgets/view_model_builder.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// "Choose a server": the searchable list of public Matrix servers, in
/// Vibe's style (plain rows on a soft card, a check on the chosen one).
class SignInPage extends StatelessWidget {
  final bool signUp;
  const SignInPage({required this.signUp, super.key});

  @override
  Widget build(BuildContext context) {
    return VibeSettingsTheme(
      child: ViewModelBuilder(
        create: () => SignInViewModel(Matrix.of(context), signUp: signUp),
        builder: (context, viewModel, _) {
          final state = viewModel.value;
          final servers = state.filteredPublicHomeservers;
          final selected = state.selectedHomeserver;
          final loading =
              state.loginLoading.connectionState == ConnectionState.waiting;
          final t1 = VibeSettingsStyle.text(context);
          final t2 = VibeSettingsStyle.text2(context);
          final card = VibeSettingsStyle.card(context);
          return Scaffold(
            appBar: AppBar(
              leading: loading
                  ? CloseButton(
                      onPressed: () =>
                          viewModel.setLoginLoading(AsyncSnapshot.nothing()),
                    )
                  : BackButton(onPressed: Navigator.of(context).pop),
              title: const Text(
                'Choose a server',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Your account lives on a server. Pick any — people on '
                    'every server can chat with each other.',
                    style: TextStyle(fontSize: 13.5, height: 1.35, color: t2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    readOnly:
                        state.publicHomeservers.connectionState ==
                            ConnectionState.waiting ||
                        loading,
                    controller: viewModel.filterTextController,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    style: TextStyle(fontSize: 15, color: t1),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: card,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: state.publicHomeservers.error
                          ?.toLocalizedString(context),
                      prefixIcon: Icon(Icons.search, size: 20, color: t2),
                      hintText: 'Search or type a server address',
                      hintStyle: TextStyle(fontSize: 15, color: t2),
                    ),
                  ),
                ),
                Expanded(
                  child:
                      state.publicHomeservers.connectionState ==
                          ConnectionState.done
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: servers.length,
                          itemBuilder: (context, i) {
                            final server = servers[i];
                            final first = i == 0;
                            final last = i == servers.length - 1;
                            return _ServerRow(
                              server: server,
                              selected: server == selected,
                              enabled: !loading,
                              first: first,
                              last: last,
                              onTap: () => viewModel.selectHomeserver(server),
                            );
                          },
                        )
                      : const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                ),
              ],
            ),
            bottomNavigationBar: AnimatedSize(
              duration: VibeThemes.animationDuration,
              curve: VibeThemes.animationCurve,
              child: selected == null || !servers.contains(selected)
                  ? const SizedBox.shrink()
                  : SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: VibeSettingsStyle.accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(fontFamily: 'Figtree', 
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onPressed: loading
                                ? null
                                : () => connectToHomeserverFlow(
                                    selected,
                                    context,
                                    viewModel.setLoginLoading,
                                    signUp,
                                  ),
                            child: loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text('Continue with ${selected.name ?? 'server'}'),
                          ),
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// One server: initial, name, short description, a few facts, a check
/// when chosen. Rows join into one rounded card.
class _ServerRow extends StatelessWidget {
  final PublicHomeserverData server;
  final bool selected;
  final bool enabled;
  final bool first;
  final bool last;
  final VoidCallback onTap;
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.enabled,
    required this.first,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final name = server.name ?? 'Unknown';
    final website = server.website;
    final facts = [
      ...?server.languages?.take(2),
      ...?server.features?.take(3),
    ];
    final radius = BorderRadius.vertical(
      top: Radius.circular(first ? 16 : 0),
      bottom: Radius.circular(last ? 16 : 0),
    );
    return Material(
      color: VibeSettingsStyle.card(context),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: enabled ? onTap : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? VibeSettingsStyle.accent
                          : VibeSettingsStyle.line(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : t1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: t1,
                          ),
                        ),
                        if ((server.description ?? '').isNotEmpty)
                          Text(
                            server.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              color: t2,
                            ),
                          ),
                        if (facts.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              facts.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: t2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (website != null)
                    SizedBox.square(
                      dimension: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        tooltip: website,
                        icon: Icon(Icons.open_in_new, size: 16, color: t2),
                        onPressed: () => launchUrlString(website),
                      ),
                    ),
                  SizedBox(
                    width: 28,
                    height: 32,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: selected
                          ? Icon(
                              Icons.check_circle,
                              key: ValueKey(true),
                              size: 22,
                              color: VibeSettingsStyle.accent,
                            )
                          : Icon(
                              Icons.circle_outlined,
                              key: const ValueKey(false),
                              size: 22,
                              color: VibeSettingsStyle.line(context),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (!last)
              Padding(
                padding: const EdgeInsets.only(left: 62),
                child: Container(
                  height: 0.6,
                  color: VibeSettingsStyle.line(context),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
