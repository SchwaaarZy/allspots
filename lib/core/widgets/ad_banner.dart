import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdBanner extends StatefulWidget {
  final AdSize size;

  const AdBanner({
    super.key,
    this.size = AdSize.banner,
  });

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _shouldShowAd = true;

  bool get _isAdsSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _checkAdStatus();
  }

  Future<void> _checkAdStatus() async {
    if (!_isAdsSupported) {
      setState(() => _shouldShowAd = false);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _loadAd();
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();
      if (data == null) {
        _loadAd();
        return;
      }

      final isPremium = data['isPremium'] ?? false;
      final premiumExpiry = data['premiumExpiryDate'] as Timestamp?;

      if (isPremium && premiumExpiry != null) {
        final expiryDate = premiumExpiry.toDate();
        if (DateTime.now().isBefore(expiryDate)) {
          setState(() => _shouldShowAd = false);
          return;
        }
      }

      final demoExpiry = data['demoNoAdsExpiry'] as Timestamp?;
      if (demoExpiry != null) {
        final expiryDate = demoExpiry.toDate();
        if (DateTime.now().isBefore(expiryDate)) {
          setState(() => _shouldShowAd = false);
          return;
        }
      }

      _loadAd();
    } catch (e) {
      _loadAd();
    }
  }

  void _loadAd() {
    final ad = BannerAd(
      size: widget.size,
      adUnitId: _getAdUnitId(),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );

    ad.load();
  }

  String _getAdUnitId() {
    return 'ca-app-pub-3940256099942544/6300978111';
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdsSupported || !_shouldShowAd) {
      return const SizedBox.shrink();
    }

    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: MediaQuery.of(context).size.width,
      height: _bannerAd!.size.height.toDouble(),
      color: Colors.white,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
