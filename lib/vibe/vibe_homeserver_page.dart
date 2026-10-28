// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/vibe/vibe_settings_style.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher_string.dart';

class VibeHomeserverPage extends StatefulWidget {
  const VibeHomeserverPage({super.key});

  @override
  _VibeHomeserverPageState createState() => _VibeHomeserverPageState();
}

class _VibeHomeserverPageState extends State<VibeHomeserverPage> {
  Future<({String name, String version, Uri federationBaseUrl})>
  fetchServerInfo() async {
    final client = Matrix.of(context).client;
    final domain = client.userID!.domain!;
    final httpClient = client.httpClient;
    var federationBaseUrl = Uri(host: domain, port: 8448, scheme: 'https');
    try {
      final serverWellKnownResult = await httpClient.get(
        Uri.https(domain, '/.well-known/matrix/server'),
      );
      final serverWellKnown = jsonDecode(serverWellKnownResult.body);
      federationBaseUrl = Uri.https(serverWellKnown['m.server']);
    } catch (e, s) {
      Logs().w(
        'Unable to fetch federation base uri. Use $federationBaseUrl',
        e,
        s,
      );
    }

    final serverVersionResult = await http.get(
      federationBaseUrl.resolveUri(Uri(path: '/_matrix/federation/v1/version')),
    );
    final {
      'server': {'name': String name, 'version': String version},
    } = Map<String, Map<String, dynamic>>.from(
      jsonDecode(serverVersionResult.body),
    );

    return (name: name, version: version, federationBaseUrl: federationBaseUrl);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !VibeThemes.isColumnMode(context),
        centerTitle: VibeThemes.isColumnMode(context),
        title: Text(
          L10n.of(
            context,
          ).aboutHomeserver(client.userID?.domain ?? 'Homeserver'),
        ),
      ),
      body: MaxWidthBody(
        withScrolling: true,
        child: SelectionArea(
          child: VibeGroups(
            children: [
              ListTile(
                title: Text(
                  L10n.of(context).serverInformation,
                  style: TextStyle(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FutureBuilder(
                future: client.getWellknownSupport(),
                builder: (context, snapshot) {
                  final error = snapshot.error;
                  final data = snapshot.data;
                  if (error != null) {
                    return ListTile(
                      leading: const Icon(Icons.error_outlined),
                      title: Text(
                        error.toLocalizedString(
                          context,
                          ExceptionContext.checkServerSupportInfo,
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }
                  if (data == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    );
                  }
                  final supportPage = data.supportPage;
                  final contacts = data.contacts;
                  if (supportPage == null && contacts == null) {
                    return ListTile(
                      leading: const Icon(Icons.error_outlined),
                      title: Text(
                        L10n.of(context).noContactInformationProvided,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }
                  return Column(
                    mainAxisSize: .min,
                    children: [
                      if (supportPage != null)
                        ListTile(
                          title: Text(L10n.of(context).supportPage),
                          subtitle: Text(supportPage.toString()),
                        ),
                      if (contacts != null)
                        ...contacts.map((contact) {
                          return ListTile(
                            title: Text(
                              contact.role.localizedString(L10n.of(context)),
                            ),
                            subtitle: Column(
                              mainAxisSize: .min,
                              children: [
                                if (contact.emailAddress != null)
                                  TextButton(
                                    onPressed: () {},
                                    child: Text(contact.emailAddress!),
                                  ),
                                if (contact.matrixId != null)
                                  TextButton(
                                    onPressed: () {},
                                    child: Text(contact.matrixId!),
                                  ),
                              ],
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
              FutureBuilder(
                future: fetchServerInfo(),
                builder: (context, snapshot) {
                  final error = snapshot.error;
                  if (error != null) {
                    return Column(
                      mainAxisAlignment: .center,
                      children: [
                        Icon(
                          Icons.error_outlined,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          error.toLocalizedString(context),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    );
                  }
                  return Column(
                    mainAxisSize: .min,
                    children: [
                      ListTile(
                        title: Text(L10n.of(context).name),
                        subtitle: Text(data.name),
                      ),
                      ListTile(
                        title: Text(L10n.of(context).version),
                        subtitle: Text(data.version),
                      ),
                      ListTile(
                        title: Text(L10n.of(context).federationBaseUrl),
                        subtitle: Linkify(
                          text: data.federationBaseUrl.toString(),
                          textScaleFactor: MediaQuery.textScalerOf(
                            context,
                          ).scale(1),
                          options: const LinkifyOptions(humanize: false),
                          linkStyle: TextStyle(
                            color: theme.colorScheme.primary,
                            decorationColor: theme.colorScheme.primary,
                          ),
                          onOpen: (link) => launchUrlString(link.url),
                        ),
                      ),
                    ],
                  );
                },
              ),
              Divider(color: theme.dividerColor),
              FutureBuilder(
                future: client.getWellknown(),
                builder: (context, snapshot) {
                  final error = snapshot.error;
                  if (error != null) {
                    return Column(
                      mainAxisAlignment: .center,
                      children: [
                        Icon(
                          Icons.error_outlined,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          error.toLocalizedString(context),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                    );
                  }
                  final wellKnown = snapshot.data;
                  if (wellKnown == null) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    );
                  }
                  final identityServer = wellKnown.mIdentityServer;
                  return Column(
                    mainAxisSize: .min,
                    children: [
                      ListTile(
                        title: Text(
                          L10n.of(context).clientWellKnownInformation,
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ListTile(
                        title: Text(L10n.of(context).baseUrl),
                        subtitle: Linkify(
                          text: wellKnown.mHomeserver.baseUrl.toString(),
                          textScaleFactor: MediaQuery.textScalerOf(
                            context,
                          ).scale(1),
                          options: const LinkifyOptions(humanize: false),
                          linkStyle: TextStyle(
                            color: theme.colorScheme.primary,
                            decorationColor: theme.colorScheme.primary,
                          ),
                          onOpen: (link) => launchUrlString(link.url),
                        ),
                      ),
                      if (identityServer != null)
                        ListTile(
                          title: Text(L10n.of(context).identityServer),
                          subtitle: Linkify(
                            text: identityServer.baseUrl.toString(),
                            textScaleFactor: MediaQuery.textScalerOf(
                              context,
                            ).scale(1),
                            options: const LinkifyOptions(humanize: false),
                            linkStyle: TextStyle(
                              color: theme.colorScheme.primary,
                              decorationColor: theme.colorScheme.primary,
                            ),
                            onOpen: (link) => launchUrlString(link.url),
                          ),
                        ),
                      ...wellKnown.additionalProperties.entries.map(
                        (entry) => ListTile(
                          title: Text(entry.key),
                          subtitle: Material(
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius,
                            ),
                            color: theme.colorScheme.surfaceContainer,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                const JsonEncoder.withIndent(
                                  '    ',
                                ).convert(entry.value),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


extension on Role {
  String localizedString(L10n l10n) {
    switch (this) {
      case Role.mRoleAdmin:
        return l10n.contactServerAdmin;
      case Role.mRoleSecurity:
        return l10n.contactServerSecurity;
    }
  }
}
