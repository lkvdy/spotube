import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:hetu_script/hetu_script.dart';
import 'package:hetu_std/hetu_std.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' hide Column, Row, Text;
import 'package:spotube/collections/routes.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MetadataAuthEndpoint {
  final Hetu hetu;
  final String pluginSlug;

  MetadataAuthEndpoint(this.hetu, this.pluginSlug);

  Stream get authStateStream =>
      hetu.eval("metadataPlugin.auth.authStateStream");

  Future<void> authenticate() async {
    if (pluginSlug == "spotube-plugin-youtube-audio") {
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        final cookies = await showDialog<String>(
          context: context,
          builder: (context) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text("YouTube Login (Cookies)"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Paste your YouTube cookies here (VISITOR_INFO1_LIVE, SID, etc.)",
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 5,
                    placeholder: const Text("Paste cookies..."),
                  ),
                ],
              ),
              actions: [
                Button.secondary(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                Button.primary(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );

        if (cookies != null && cookies.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString("youtube_auth_cookies", cookies);
          // Trigger a reload or notification if needed
        }
        return;
      }
    }
    await hetu.eval("metadataPlugin.auth.authenticate()");
  }

  bool isAuthenticated() {
    if (pluginSlug == "spotube-plugin-youtube-audio") {
      // Logic to check if cookies are stored and valid
      return true; // Simplification for now
    }
    return hetu.eval("metadataPlugin.auth.isAuthenticated()") as bool;
  }

  Future<void> logout() async {
    if (pluginSlug == "spotube-plugin-youtube-audio") {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("youtube_auth_cookies");
      return;
    }
    await hetu.eval("metadataPlugin.auth.logout()");
    if (kIsMobile) {
      WebStorageManager.instance().deleteAllData();
      CookieManager.instance().deleteAllCookies();
    }
    if (kIsDesktop) {
      await WebviewWindow.clearAll();
    }
  }
}
