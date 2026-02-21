import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class InstallationInfoTab extends StatelessWidget {
  const InstallationInfoTab({super.key});

  // Renseignez vos URLs finales.
  static const String androidApkUrl = '';
  static const String googlePlayUrl = '';
  static const String iosDownloadUrl = '';
  static const String appStoreUrl = '';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: const [
        _TitleBlock(
          title: 'Installation',
          subtitle: 'Choisissez votre plateforme pour télécharger AllSpots.',
        ),
        SizedBox(height: 10),
        _PlatformCard(
          title: 'Android',
          subtitle: 'Téléchargez l’APK officiel ou installez via le store.',
          icon: Icons.android,
          primaryActionLabel: 'Télécharger l’APK',
          primaryUrl: androidApkUrl,
          secondaryActionLabel: 'Google Play',
          secondaryUrl: googlePlayUrl,
        ),
        _PlatformCard(
          title: 'iPhone / iPad',
          subtitle: 'Installez l’application via le web ou l’App Store.',
          icon: Icons.apple,
          primaryActionLabel: 'Télécharger l’app',
          primaryUrl: iosDownloadUrl,
          secondaryActionLabel: 'App Store',
          secondaryUrl: appStoreUrl,
        ),
        SizedBox(height: 18),
        _Footer(),
      ],
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryActionLabel,
    required this.primaryUrl,
    required this.secondaryActionLabel,
    required this.secondaryUrl,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  final String primaryActionLabel;
  final String primaryUrl;
  final String secondaryActionLabel;
  final String secondaryUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _LinkButton(
                  label: primaryActionLabel,
                  url: primaryUrl,
                  isPrimary: true,
                ),
                _LinkButton(
                  label: secondaryActionLabel,
                  url: secondaryUrl,
                  isPrimary: false,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Astuce : ajoutez vos URLs finales (APK / stores) dans le fichier installation_info_tab.dart.',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.url, required this.isPrimary});

  final String label;
  final String url;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final enabled = url.trim().isNotEmpty;

    return ElevatedButton.icon(
      onPressed: enabled
          ? () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Lien copié : $label'),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          : null,
      icon: Icon(enabled ? Icons.copy : Icons.link_off, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? Theme.of(context).colorScheme.primary : Colors.white,
        foregroundColor: isPrimary ? Colors.white : Theme.of(context).colorScheme.primary,
        disabledBackgroundColor: const Color(0xFFE5E7EB),
        disabledForegroundColor: const Color(0xFF6B7280),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: isPrimary ? BorderSide.none : const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    return Center(
      child: Text(
        '© $year AllSpots',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
    );
  }
}
