import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:algolia/algolia.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:click/app/recipes.dart';
import 'package:click/app/promotions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/callable_retry.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/login_page.dart';
import '../../custom_page_route.dart';
import '../components/bottom_fade.dart';
import '../components/custom_loader.dart';
import '../components/shimmer_placeholder.dart';
import '../constants/app_images.dart';
import 'cart/cart_provider.dart';
import 'category/filter_dialog.dart';
import 'category/product_display.dart';
import 'category/variant_expansion.dart';
import 'game/arcade_center_screen.dart';
import 'constants/gridview.dart';
import 'ads_carousel.dart';
import 'home_blocks.dart';
import 'combos/combo_detail.dart';

void testNetworkAccess() async {
  try {
    final result =
    await InternetAddress.lookup('pdtyztlt1bpdtyztlt1b-3.algolianet.com');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
      if (kDebugMode) {
        print('Algolia host is reachable');
      }
    }
  } on SocketException catch (_) {
    if (kDebugMode) {
      print('Algolia host is not reachable');
    }
  }
}

class AlgoliaService {
  static const Algolia _algolia = Algolia.init(
    applicationId: '55OV27NTPC',
    apiKey: 'c72bcb855854751e436dd24b54844233',
  );

  Algolia get algolia => _algolia;
}

class Home extends StatefulWidget {
  final void Function(int tabIndex)? onSwitchTab;

  const Home({super.key, this.onSwitchTab});

  @override
  State<Home> createState() => HomeState();
}

class HomeState extends State<Home>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  // FocusNode lets us drive the search-mode UI off focus state, not
  // just the typed text — so the home content fades out the moment
  // the user taps into the field, before they've typed anything.
  final FocusNode _searchFocus = FocusNode();
  // Mirrored in state because AnimatedSwitcher needs a setState
  // signal when focus flips. Kept in sync via the focus listener.
  bool _searchFocused = false;
  // Tracks the previous viewInsets.bottom so didChangeMetrics can
  // detect the keyboard-just-closed transition. Initial value
  // matches the "keyboard not open at app start" baseline.
  bool _wasKeyboardOpen = false;
  String _searchText = '';
  // Debounces Algolia network calls so we fire one query when typing
  // pauses, not one per keystroke. Cancelled in dispose and on every
  // new keystroke.
  Timer? _searchDebounce;

  List<DocumentSnapshot> _searchResults = [];
  bool _isSearching = false;
  bool _showRecipeDetail = false;
  bool _showPromoDetail = false;
  bool _showProductDisplay = false;
  String? _pdCategory;
  String? _pdBrand;
  String? _pdDistributor;
  List<String>? _pdProductIds;
  String? _pdTitle;
  String? _pdImageUrl;
  bool _showComboDetail = false;
  String? _comboId;
  Map<String, dynamic> _selectedFilters = {};
  String? selectedRecipeId;
  String? selectedPromoId;
  List<DocumentSnapshot> _filteredProducts = [];

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _homeSectionsStream =
      FirebaseFirestore.instance.collection('home_sections').snapshots();

  final PageController _pageController = PageController();

  String?            _pendingUid;
  DocumentReference? _pendingRewardsRef;
  double             _pendingSaldo = 0;
  late AnimationController _shakeCtrl;
  late Animation<double>   _shakeAnim;

  bool _crtActive = false;
  late final AnimationController _crtCtrl;
  late final Animation<double> _crtSquish;
  late final Animation<double> _crtLine;
  late final Animation<double> _crtFade;
  OverlayEntry? _crtBlackOverlay;

  late final AnimationController _spinCtrl;
  Timer? _spinTimer;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _saldoSub;
  double _walletSaldo = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
    WidgetsBinding.instance.addObserver(this);

    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -7.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -7.0, end: 7.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 7.0, end: -4.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.linear));

    _crtCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
    _crtSquish = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(parent: _crtCtrl,
            curve: const Interval(0.0, 0.58, curve: Curves.easeIn)));
    _crtLine = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _crtCtrl,
        curve: const Interval(0.44, 0.80)));
    _crtFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _crtCtrl,
            curve: const Interval(0.65, 1.0, curve: Curves.easeIn)));
    _crtCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && _crtActive && mounted) {
        _navigateToArcade();
      }
    });

    _spinCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _spinTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_spinCtrl.isAnimating) _spinCtrl.forward(from: 0);
    });
    _initSaldoListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchFocus.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    _pageController.dispose();
    _shakeCtrl.dispose();
    _crtCtrl.dispose();
    _spinTimer?.cancel();
    _spinCtrl.dispose();
    _saldoSub?.cancel();
    _crtBlackOverlay?.remove();
    _crtBlackOverlay = null;
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (!mounted) return;
    final hasFocus = _searchFocus.hasFocus;
    if (_searchFocused != hasFocus) {
      setState(() => _searchFocused = hasFocus);
    }
  }

  /// Watch for the keyboard-just-closed transition. When the OS
  /// dismisses the keyboard (system back button, swipe-down, etc.)
  /// AND the search bar is still focused with no text, we drop the
  /// focus so the home view smoothly fades back in. If the user
  /// typed something, focus is kept — they should still see their
  /// results until they explicitly clear the bar.
  ///
  /// Reading viewInsets from `View.of(context)` directly because
  /// `MediaQuery.of(context)` updates asynchronously after metrics
  /// change, so it can lag a frame behind reality here.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final view = View.of(context);
    final keyboardOpen = view.viewInsets.bottom > 0;
    if (_wasKeyboardOpen && !keyboardOpen) {
      if (_searchFocus.hasFocus &&
          _searchController.text.trim().isEmpty) {
        _searchFocus.unfocus();
      }
    }
    _wasKeyboardOpen = keyboardOpen;
  }

  bool get _inSearchMode =>
      _searchFocused || _isSearching || _searchText.isNotEmpty;

  /// Refresh saldo when the app returns to the foreground. The
  /// home now reads saldo via `getRewardsBalance` (callable) rather
  /// than a Firestore stream, so we lose real-time updates. The
  /// most common stale-saldo scenarios — PDV-side recharge, order
  /// placement debit, claim-coupon top-up — all coincide with the
  /// user putting the app in the background and re-opening it.
  /// Polling on resume covers them with one round-trip.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshSaldo();
    }
  }

  void _onSearchChanged() {
    // Cancel any pending fire — the user is still typing.
    _searchDebounce?.cancel();
    setState(() {
      _searchText = _searchController.text;
      if (_searchText.isNotEmpty) {
        // Flip the spinner on immediately so the UI feels responsive
        // even though the network call waits for typing to settle.
        _isSearching = true;
      } else {
        // Clearing happens instantly — no network call to debounce.
        _isSearching = false;
        _searchResults = [];
      }
    });
    if (_searchText.isNotEmpty) {
      final pending = _searchText;
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        // Guard against a stale fire — if the text changed between
        // scheduling and now, a newer Timer will (or has) handled it.
        if (_searchController.text != pending) return;
        _searchAlgolia(pending);
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedFilters = {};
      _filteredProducts = [];
      _searchController.clear();
    });
  }

  void _applyFilters(Map<String, dynamic> filters) {
    setState(() {
      _selectedFilters = filters;
    });

    final subCategory = filters['subCategory'];
    final priceRange = filters['priceRange'] as RangeValues;

    Query query = FirebaseFirestore.instance.collection('products');

    if (subCategory != null && subCategory.isNotEmpty) {
      query = query.where('category', isEqualTo: subCategory);
    }

    query = query
        .where('price', isGreaterThanOrEqualTo: priceRange.start)
        .where('price', isLessThanOrEqualTo: priceRange.end);

    query.get().then((snapshot) {
      // Guard against the user navigating away mid-query — without
      // this the .then() lands on a defunct State and Flutter
      // throws `setState() called after dispose()`.
      if (!mounted) return;
      final docs = snapshot.docs
          .where((d) =>
              ((d.data() as Map<String, dynamic>?)?['hide_online'] as bool?) !=
              true)
          .toList()
        ..sort((a, b) {
          final an = ((a.data() as Map<String, dynamic>?)?['nombre'] ?? '')
              .toString()
              .toLowerCase();
          final bn = ((b.data() as Map<String, dynamic>?)?['nombre'] ?? '')
              .toString()
              .toLowerCase();
          return an.compareTo(bn);
        });
      setState(() {
        _filteredProducts = docs;
      });
    });
  }

  String _normalizeForSearch(String s) {
    s = s.toLowerCase().trim();
    const accents = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    accents.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    List<int> prev = List<int>.generate(t.length + 1, (i) => i);
    List<int> curr = List<int>.filled(t.length + 1, 0);
    for (int i = 0; i < s.length; i++) {
      curr[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        final del = curr[j] + 1;
        final ins = prev[j + 1] + 1;
        final sub = prev[j] + cost;
        curr[j + 1] =
            del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[t.length];
  }

  bool _fuzzyMatch(String text, String query) {
    if (query.isEmpty) return true;
    if (text.contains(query)) return true;
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final tokens =
        query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return false;
    for (final token in tokens) {
      final maxDist = token.length <= 4 ? 1 : 2;
      final ok = words
          .any((w) => w.contains(token) || _levenshtein(token, w) <= maxDist);
      if (!ok) return false;
    }
    return true;
  }

  Future<void> _searchAlgolia(String searchText) async {
    setState(() {
      _isSearching = true;
    });
    Algolia algolia = AlgoliaService().algolia;
    // Cap the hit count — the search list is for typeahead, 12 is plenty and
    // it keeps the Firestore hydrate inside ONE whereIn chunk (cap = 30).
    AlgoliaQuery query = algolia.instance
        .index('t_sty.db')
        .query(searchText)
        .setHitsPerPage(12);

    try {
      if (kDebugMode) {
        print('Querying Algolia with: $searchText');
      }
      AlgoliaQuerySnapshot snapshot = await query.getObjects();
      final String q = _normalizeForSearch(searchText);

      final algoliaHits = snapshot.hits.where((h) {
        if ((h.data['hide_online'] as bool?) == true) return false;
        final name = _normalizeForSearch((h.data['nombre'] ?? '').toString());
        final variante =
            _normalizeForSearch((h.data['variante'] ?? '').toString());
        return _fuzzyMatch(name, q) || _fuzzyMatch(variante, q);
      }).toList()
        ..sort((a, b) {
          final an = _normalizeForSearch((a.data['nombre'] ?? '').toString());
          final bn = _normalizeForSearch((b.data['nombre'] ?? '').toString());
          final aExact = an.contains(q) ? 0 : 1;
          final bExact = bn.contains(q) ? 0 : 1;
          if (aExact != bExact) return aExact - bExact;
          return an.compareTo(bn);
        });

      final ids = algoliaHits.map((h) => h.objectID).toList();
      final hydrated = await _hydrateProductDocs(ids);

      final filtered = hydrated.where((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return false;
        if ((data['hide_online'] as bool?) == true) return false;
        final name = _normalizeForSearch((data['nombre'] ?? '').toString());
        final variante =
            _normalizeForSearch((data['variante'] ?? '').toString());
        if (_fuzzyMatch(name, q) || _fuzzyMatch(variante, q)) return true;
        if (data['has_variants'] == true && data['variants'] is Map) {
          for (final v in (data['variants'] as Map).values) {
            if (v is Map) {
              final vn = _normalizeForSearch((v['name'] ?? '').toString());
              if (_fuzzyMatch(vn, q)) return true;
            }
          }
        }
        return false;
      }).toList();

      if (!mounted) return;
      setState(() {
        _searchResults = filtered;
        _isSearching = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error: $e");
      }
      if (!mounted) return;
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<List<DocumentSnapshot>> _hydrateProductDocs(
      List<String> ids) async {
    if (ids.isEmpty) return const [];
    // Build chunks of 10 (Firestore whereIn cap is 30, kept at 10 for room
    // to grow filters) and fire them in PARALLEL via Future.wait. The
    // previous for-await loop was serial — at default hitsPerPage=20 that
    // doubled the wall-clock added to every Algolia search. The hits cap
    // (setHitsPerPage(12) in _searchAlgolia) keeps this to ONE chunk for
    // the typical query, but the parallel shape stays robust if it's ever
    // raised.
    final chunks = <List<String>>[];
    for (int i = 0; i < ids.length; i += 10) {
      chunks.add(ids.sublist(
          i, i + 10 > ids.length ? ids.length : i + 10));
    }
    final results = await Future.wait(
      chunks.map((chunk) async {
        try {
          return await FirebaseFirestore.instance
              .collection('products')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
        } catch (e) {
          if (kDebugMode) print('Hydrate chunk error: $e');
          return null;
        }
      }),
    );
    final fetched = <String, DocumentSnapshot>{};
    for (final snap in results) {
      if (snap == null) continue;
      for (final d in snap.docs) {
        fetched[d.id] = d;
      }
    }
    return [
      for (final id in ids)
        if (fetched.containsKey(id)) fetched[id]!,
    ];
  }

  void _navigateToRecipeDetail(String recipeId) {
    setState(() {
      selectedRecipeId = recipeId;
      _showRecipeDetail = true;
    });
  }

  void _navigateBackToGrid() {
    setState(() {
      _showRecipeDetail = false;
      _showPromoDetail = false;
      _showProductDisplay = false;
      _showComboDetail = false;
    });
  }

  bool handleBack() {
    if (_showRecipeDetail ||
        _showPromoDetail ||
        _showProductDisplay ||
        _showComboDetail) {
      _navigateBackToGrid();
      return true;
    }
    return false;
  }

  void _openCombo(String comboId) {
    setState(() {
      _comboId = comboId;
      _showComboDetail = true;
    });
  }

  void _navigateToPromoDetail(String promoId) {
    setState(() {
      selectedPromoId = promoId;
      _showPromoDetail = true;
    });
  }

  void _openProductDisplay({
    String? category,
    String? brand,
    String? provedor,
    List<String>? productIds,
    String? title,
    String? imageUrl,
  }) {
    setState(() {
      _pdCategory = category;
      _pdBrand = brand;
      _pdDistributor = provedor;
      _pdProductIds = productIds;
      _pdTitle = title;
      _pdImageUrl = imageUrl;
      _showProductDisplay = true;
    });
  }

  /// Fetches the signed-in user's wallet saldo via the
  /// `getRewardsBalance` Cloud Function. The previous version
  /// streamed `rewards/{docId}` directly from the client, which the
  /// security rules deny to non-admins (the rewards collection is
  /// admin-only by design — PIN/CVV/PII can't be read). The result
  /// was that the arcade icon only appeared for admin accounts.
  ///
  /// The callable returns just `{saldo, hasWallet}` — no PII — so we
  /// keep the existing security model intact while making the icon
  /// visible to every signed-in user. We trade real-time updates
  /// (the old snapshots() listener) for a polled read: we refresh
  /// on init AND every time the app returns to the foreground
  /// (`didChangeAppLifecycleState.resumed`), which is plenty fresh
  /// for an icon visibility toggle.
  Future<void> _initSaldoListener() async {
    await _refreshSaldo();
  }

  Future<void> _refreshSaldo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted && _walletSaldo != 0) {
        setState(() => _walletSaldo = 0);
      }
      return;
    }

    // Retries transient cold-launch failures (network/function warmup) so the
    // saldo loads on first launch instead of staying blank until app resume.
    try {
      final res = await callIdempotentCallable('getRewardsBalance');
      final data = res.data;
      if (data is Map) {
        // `hasWallet:false` means the wallet LINK failed to resolve (missing
        // cardInfo, missing cardNumber, or an empty rewards query) — it is NOT
        // a zero balance. Writing that 0 in blanked healthy wallets and, since
        // the arcade icon is gated on `_walletSaldo`, made the icon vanish too.
        // Keep whatever we already had and let the next resume retry.
        if (data['hasWallet'] == false) {
          if (kDebugMode) {
            debugPrint('getRewardsBalance: wallet unresolved; keeping cached saldo');
          }
          return;
        }
        final raw = data['saldo'];
        final s = raw is num
            ? raw.toDouble()
            : (raw is String ? (double.tryParse(raw) ?? 0.0) : 0.0);
        if (mounted && s != _walletSaldo) {
          setState(() => _walletSaldo = s);
        }
      }
    } catch (e) {
      // Leave the cached value so a hiccup doesn't blank the icon mid-session;
      // it'll refresh on the next app resume.
      if (kDebugMode) debugPrint('getRewardsBalance failed: $e');
    }
  }

  Future<void> _launchGame() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    // Saldo + wallet lookup — both routed through the
    // `getRewardsBalance` Cloud Function so non-admin users don't
    // hit PERMISSION_DENIED on the admin-only `rewards` collection.
    // We force a fresh read here (instead of trusting the cached
    // `_walletSaldo`) so a brand-new install / fresh sign-in still
    // gets a correct gate-check without waiting for the next
    // app-resume tick.
    await _refreshSaldo();
    if (!mounted) return;
    if (_walletSaldo < 5) return;

    // The 11 arcade game widgets accept a `rewardsDocRef` param but
    // none of them DEREFERENCE it any more (the Phase 2 refactor
    // routes every saldo move through the `updateRewardsSaldo`
    // callable, which resolves the wallet server-side from auth).
    // The widget signatures still require a `DocumentReference`,
    // so we pass the owner-readable `users/{uid}/rewardsCard/cardInfo`
    // doc as a harmless placeholder. If a future game ever tries
    // to use the ref, it'll read a doc the client owns rather than
    // hitting the admin-only `rewards` collection.
    final placeholderRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rewardsCard')
        .doc('cardInfo');

    _pendingUid        = uid;
    _pendingRewardsRef = placeholderRef;
    _pendingSaldo      = _walletSaldo;
    if (!_crtActive) {
      setState(() => _crtActive = true);
      _crtBlackOverlay = OverlayEntry(
        builder: (_) => AnimatedBuilder(
          animation: _crtFade,
          builder: (_, __) {
            if (_crtFade.value <= 0.01) return const SizedBox.shrink();
            return ColoredBox(color: Colors.black.withOpacity(_crtFade.value));
          },
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(_crtBlackOverlay!);
      _crtCtrl.forward();
    }
  }

  Widget _buildGameIcon(bool isDarkMode) {
    return RotationTransition(
      turns: _spinCtrl.drive(CurveTween(curve: Curves.elasticOut)),
      child: IconButton(
        tooltip: 'Arcade',
        splashRadius: 22,
        icon: Icon(
          Icons.sports_esports,
          size: 28,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
        onPressed: _launchGame,
      ),
    );
  }

  void _navigateToArcade() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => _ArcadeLaunchPage(
          userId: _pendingUid!,
          rewardsDocRef: _pendingRewardsRef!,
          currentSaldo: _pendingSaldo,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _crtActive = false);
        _crtCtrl.reset();
      }
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      _crtBlackOverlay?.remove();
      _crtBlackOverlay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bool showGameIcon =
        FirebaseAuth.instance.currentUser != null && _walletSaldo >= 5;

    final body = Scaffold(
        // Keep the layout from collapsing under the keyboard. The
        // BottomFade sits inside an Expanded; if the body shrinks
        // when the keyboard opens, LayoutBuilder reports a smaller
        // maxHeight and the fade rides up above the keyboard,
        // detaching from the nav bar. With this off, the fade and
        // nav stay pinned to the screen bottom and the keyboard
        // simply overlays the lower portion of the product grid —
        // which is what you want when the user is mid-search.
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          leadingWidth: showGameIcon ? 48 : null,
          leading: showGameIcon ? const SizedBox(width: 48) : null,
          title: SizedBox(
            height: 180,
            width: 300,
            child: AspectRatio(
              aspectRatio: 1 / 1,
              child: AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(_shakeAnim.value, 0),
                    child: child,
                  ),
                  child: Image.asset(
                    isDarkMode ? AppImages.logowhite : AppImages.logo,
                    fit: BoxFit.contain,
                  ),
                ),
            ),
          ),
          centerTitle: true,
          actions: [if (showGameIcon) _buildGameIcon(isDarkMode)],
        ),
        body: IndexedStack(
          index: _showComboDetail
              ? 4
              : _showProductDisplay
                  ? 3
                  : (_showRecipeDetail ? 1 : (_showPromoDetail ? 2 : 0)),
          children: [
            Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      decoration: InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged();
                          },
                        )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDarkMode
                            ? Colors.grey[850]
                            : Colors.grey[200],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: () async {
                      final result =
                          await showFilterSheet(context, _selectedFilters);

                      if (result != null) {
                        if (result['clear'] == true) {
                          _clearFilters();
                        } else {
                          setState(() {
                            _selectedFilters = result;
                          });
                          _applyFilters(result);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: BottomFade(
                clearHeight: 96,
                fadeHeight: 48,
                // Crossfade between two top-level modes:
                //   * Search mode — triggered by focus, in-flight
                //     query, OR existing typed text. Renders a
                //     skeleton list while empty / loading, real
                //     results once they land.
                //   * Home mode — the usual filtered or default
                //     product grids.
                // Keyed subtrees so AnimatedSwitcher knows to run
                // the FadeTransition when we flip modes; same key
                // would just rebuild in place.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _inSearchMode
                      ? KeyedSubtree(
                          key: const ValueKey('home-search-mode'),
                          child: _buildSearchModePane(),
                        )
                      : KeyedSubtree(
                          key: const ValueKey('home-grids-mode'),
                          child: _selectedFilters.isNotEmpty
                              ? _buildFilteredProductList()
                              : _buildProductGrids(),
                        ),
                ),
              ),
            ),
          ],
            ),
            _showRecipeDetail && selectedRecipeId != null
                ? RecipeDetailPage(
                    recipeId: selectedRecipeId!,
                    onBackPressed: _navigateBackToGrid,
                  )
                : const SizedBox.shrink(),
            _showPromoDetail && selectedPromoId != null
                ? PromotionDetailPage(
                    promotionId: selectedPromoId!,
                    onBackPressed: _navigateBackToGrid,
                  )
                : const SizedBox.shrink(),
            _showProductDisplay
                ? ProductDisplayPage(
                    key: ValueKey('pd_${_pdTitle}_${_pdCategory}_'
                        '${_pdBrand}_${_pdDistributor}_'
                        '${_pdProductIds?.join(',')}_$_pdImageUrl'),
                    selectedCategory: _pdCategory,
                    brand: _pdBrand,
                    distributorName: _pdDistributor,
                    productIds: _pdProductIds,
                    title: _pdTitle,
                    imageUrl: _pdImageUrl,
                    onBack: _navigateBackToGrid,
                  )
                : const SizedBox.shrink(),
            _showComboDetail && _comboId != null
                ? ComboDetailPage(
                    key: ValueKey('combo_$_comboId'),
                    comboId: _comboId!,
                    onBack: _navigateBackToGrid,
                  )
                : const SizedBox.shrink(),
          ],
        ),
      );

    return AnimatedBuilder(
      animation: _crtCtrl,
      builder: (ctx, child) {
        return Stack(children: [
          Transform(
            alignment: Alignment.center,
            transform: _crtActive
                ? Matrix4.diagonal3Values(1.0, _crtSquish.value, 1.0)
                : Matrix4.identity(),
            child: child!,
          ),
          if (_crtActive && _crtLine.value > 0.01)
            Positioned.fill(
                child: ColoredBox(
                    color: Colors.white.withOpacity(_crtLine.value * 0.92))),
        ]);
      },
      child: body,
    );
  }

  Widget _buildFilteredProductList() {
    if (_filteredProducts.isEmpty) {
      return const Center(
          child: Text('No se encontraron productos con los filtros aplicados.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        var product = _filteredProducts[index];
        return _buildListItem(context, product);
      },
    );
  }

  Widget _buildProductGrids() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _homeSectionsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.only(top: 60),
                child: CustomLoader(),
              );
            }

            final docs = (snapshot.data?.docs ?? [])
                .where((d) => (d.data()['enabled'] as bool?) ?? true)
                .toList()
              ..sort((a, b) => ((a.data()['order'] as num?) ?? 0)
                  .compareTo((b.data()['order'] as num?) ?? 0));

            final List<Widget> sections = docs.isEmpty
                ? _defaultSections()
                : docs.map((d) => _buildSection(context, d.id, d.data())).toList();

            return Column(
              children: [
                ...sections,
                Text(
                  'Isaías 45:7–9 ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 115),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, String id, Map<String, dynamic> data) {
    final String type = data['type'] as String? ?? 'product_grid';
    final String title = data['title'] as String? ?? '';
    final Key key = ValueKey('section_$id');

    switch (type) {
      case 'product_grid':
        final source = (data['source'] as Map<String, dynamic>?) ?? const {};
        final mode = source['mode'] as String? ?? 'query';
        final orderedIds = mode == 'productIds'
            ? (source['productIds'] as List?)?.cast<String>()
            : null;
        return FirestoreProductGrid(
          key: key,
          title: title,
          query: _queryFromSource(source),
          orderedIds: orderedIds,
        );
      case 'ad_carousel':
        return AdsCarousel(
          key: key,
          placement: data['placement'] as String? ?? 'home_carousel',
          title: title,
          onProductTarget: _openProductDisplay,
          onCombo: _openCombo,
          adIds: (data['adIds'] as List?)?.cast<String>(),
        );
      case 'hero_banner':
        return HeroBanner(
          key: key,
          data: data,
          onProductTarget: _openProductDisplay,
          onCombo: _openCombo,
        );
      case 'spotlight':
        return SpotlightBlock(key: key, data: data);
      case 'combo_showcase':
        return ComboShowcase(
          key: key,
          title: title.isEmpty ? 'Combos 🍔' : title,
          onCombo: _openCombo,
        );
      case 'recipe_carousel':
        return RecipeCarousel(
          key: key,
          title: title.isEmpty ? 'Recetas' : title,
          query: FirebaseFirestore.instance.collection('recipes'),
          onRecipeSelected: _navigateToRecipeDetail,
          onSeeAll: widget.onSwitchTab == null
              ? null
              : () => widget.onSwitchTab!(0),
        );
      case 'promo_carousel':
        return PromoCarousel(
          key: key,
          title: title.isEmpty ? 'Promociones 🏷️' : title,
          onPromotionSelected: _navigateToPromoDetail,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _defaultSections() {
    return [
      RecipeCarousel(
        title: "Rincon de Recetas 🍽️",
        query: FirebaseFirestore.instance.collection('recipes'),
        onRecipeSelected: _navigateToRecipeDetail,
      ),
      FirestoreProductGrid(
        title: "¡Lo más top! 🔥",
        query: FirebaseFirestore.instance
            .collection('products')
            .orderBy('sales_in_past', descending: true)
            .limit(15),
      ),
      FirestoreProductGrid(
        title: "¡Descuentos del Dia! ✨",
        query: FirebaseFirestore.instance
            .collection('products')
            .where('current_day', isEqualTo: true)
            .limit(15),
      ),
      FirestoreProductGrid(
        title: "Nuestras Recomendaciones ✨",
        query: FirebaseFirestore.instance
            .collection('products')
            .where('recommended', isEqualTo: true)
            .limit(15),
      ),
    ];
  }

  Query<Map<String, dynamic>> _queryFromSource(Map<String, dynamic> source) {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('products');

    final mode = source['mode'] as String? ?? 'query';
    if (mode == 'productIds') {
      final ids = (source['productIds'] as List?)?.cast<String>() ?? const [];
      if (ids.isNotEmpty) {
        q = q.where(FieldPath.documentId, whereIn: ids.take(30).toList());
      }
      return q;
    }

    final filters = (source['filters'] as List?) ?? const [];
    for (final f in filters) {
      if (f is! Map) continue;
      final field = f['field'] as String?;
      if (field == null) continue;
      final op = f['op'] as String? ?? '==';
      final value = f['value'];
      switch (op) {
        case '==':
          q = q.where(field, isEqualTo: value);
          break;
        case '!=':
          q = q.where(field, isNotEqualTo: value);
          break;
        case '>':
          q = q.where(field, isGreaterThan: value);
          break;
        case '>=':
          q = q.where(field, isGreaterThanOrEqualTo: value);
          break;
        case '<':
          q = q.where(field, isLessThan: value);
          break;
        case '<=':
          q = q.where(field, isLessThanOrEqualTo: value);
          break;
        case 'array-contains':
          q = q.where(field, arrayContains: value);
          break;
      }
    }

    final orderBy = source['orderBy'];
    if (orderBy is Map && orderBy['field'] is String) {
      q = q.orderBy(orderBy['field'] as String,
          descending: (orderBy['dir'] as String?) == 'desc');
    }

    final limit = (source['limit'] as num?)?.toInt() ?? 15;
    if (limit > 0) q = q.limit(limit);
    return q;
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('No se encontraron productos.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        var product = _searchResults[index];
        return _buildListItem(context, product);
      },
    );
  }

  /// Single entry-point for the search pane shown by the home
  /// AnimatedSwitcher. Picks between three states:
  ///   * in-flight query → skeleton list
  ///   * results landed and non-empty → results list
  ///   * focused but no text (or empty results) → skeleton list as
  ///     a calm placeholder, never the old "No products found"
  ///     copy on tap (that'd be a confusing flash for the user who
  ///     just opened the bar). The empty-text case never reaches
  ///     `_buildSearchResults`, so its "No products found." copy
  ///     remains the right thing for real empty-result queries.
  Widget _buildSearchModePane() {
    if (_isSearching) return _buildSearchSkeleton();
    if (_searchText.isNotEmpty) return _buildSearchResults();
    return _buildSearchSkeleton();
  }

  /// Skeleton list shown while a search is in flight. Mirrors the
  /// real `_renderSearchRow` layout — same margins, card shadow,
  /// 90×90 image slot, three stacked text-sized bars, button-sized
  /// bar on the right — so the layout doesn't jump when results
  /// arrive. Replaces the old centred CustomLoader spinner.
  Widget _buildSearchSkeleton() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: 6,
      itemBuilder: (context, _) {
        return Container(
          margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 5.0),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(4, 4),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(10.0)),
                  child: ShimmerPlaceholder(width: 90, height: 90),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShimmerPlaceholder(width: 220, height: 14),
                      SizedBox(height: 8),
                      ShimmerPlaceholder(width: 110, height: 12),
                      SizedBox(height: 8),
                      ShimmerPlaceholder(width: 70, height: 12),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  height: 36,
                  child: ShimmerPlaceholder(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildListItem(BuildContext context, dynamic doc) {

    if (doc is DocumentSnapshot) {
      final raw = doc.data();
      final m = raw is Map<String, dynamic> ? raw : null;
      if (m != null && m['has_variants'] == true) {
        final entries = expandVariantEntries([doc]);
        if (entries.length > 1 ||
            (entries.length == 1 && entries.first.isVariant)) {
          return Column(
            children: [
              for (final e in entries) _renderSearchRow(context, doc, e),
            ],
          );
        }
      }
    }
    return _renderSearchRow(context, doc, null);
  }

  Widget _renderSearchRow(
      BuildContext context, dynamic doc, VariantEntry? entry) {
    Map<String, dynamic> data;
    String? docId;
    String? name;
    double? price;
    String? imageUrl;
    bool isBulk;
    double stock;
    String? typeSpecific;
    String? variante;
    String? variantKey;
    String? variantName;

    if (doc is AlgoliaObjectSnapshot) {
      data = doc.data;
      docId = doc.objectID;
      name = data['nombre'] as String?;
      price = (data['price'] as num?)?.toDouble();
      imageUrl = data['image_url'] as String?;
      isBulk = data['bulk'] as bool? ?? false;
      stock = (data['stock'] as num?)?.toDouble() ?? 0.0;
      typeSpecific = data['type_specific'] as String?;
      variante = data['variante'] as String?;
    } else if (doc is DocumentSnapshot) {
      data = doc.data() as Map<String, dynamic>;
      docId = doc.id;
      name = data['nombre'] as String?;
      final double parentPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
      final String parentImage = (data['image_url'] as String?) ?? '';
      final double parentStock = (data['stock'] as num?)?.toDouble() ?? 0.0;
      isBulk = data['bulk'] as bool? ?? false;
      typeSpecific = data['type_specific'] as String?;

      if (entry != null && entry.isVariant) {
        price = entry.effectivePrice(parentPrice);
        imageUrl = entry.effectiveImageUrl(parentImage);
        stock = entry.effectiveStock(parentStock);
        variante = entry.variantName;
        variantKey = entry.variantKey;
        variantName = entry.variantName;
      } else {
        price = parentPrice;
        imageUrl = parentImage;
        stock = parentStock;
        variante = data['variante'] as String?;
      }
    } else {
      return const SizedBox.shrink();
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return Container(
      margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 5.0),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(4, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10.0),
              child: CachedNetworkImage(
                imageUrl: imageUrl ?? '',
                width: 90,
                height: 90,
                fit: BoxFit.contain,
                placeholder: (context, url) =>
                const ShimmerPlaceholder(width: 90, height: 90),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name ?? 'Unnamed',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: textColor),
                  ),
                  if (variante != null && variante.isNotEmpty)
                    Text(
                      variante,
                      style: TextStyle(color: textColor, fontSize: 12),
                    ),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: isGuest ? 6.0 : 0.0,
                      sigmaY: isGuest ? 6.0 : 0.0,
                    ),
                    child: Text(
                      _formatPrice(price),
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                  if (typeSpecific != null && typeSpecific.isNotEmpty)
                    Text(
                      typeSpecific,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: _AddToCartButton(
                key: ValueKey(
                    'home-search-$docId${variantKey == null ? '' : '#$variantKey'}'),
                data: {
                  'docId': docId,
                  'nombre': name,
                  'price': price,
                  'image_url': imageUrl,
                  'bulk': isBulk,
                  'stock': stock,
                  'type_specific': typeSpecific,
                  'variante': variante,
                  if (variantKey != null) 'variantKey': variantKey,
                  if (variantName != null) 'variantName': variantName,
                },
                textColor: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    return '\$${(price as num).toStringAsFixed(2)}';
  }
}

class FirestoreProductGrid extends StatefulWidget {
  final String title;
  final Query<Map<String, dynamic>> query;
  final List<String>? orderedIds;

  const FirestoreProductGrid({
    super.key,
    required this.title,
    required this.query,
    this.orderedIds,
  });

  @override
  State<FirestoreProductGrid> createState() => _FirestoreProductGridState();
}

class _FirestoreProductGridState extends State<FirestoreProductGrid> {
  late final Stream<QuerySnapshot> _stream = widget.query.snapshots();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSection(context, widget.title),
        _buildHorizontalGridView(context),
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      itemBuilder: (context, i) => Container(
        width: 150,
        margin: const EdgeInsets.fromLTRB(8, 8, 5, 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildHorizontalGridView(BuildContext context) {
    return SizedBox(
      height: 300,
      child: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return _buildSkeletonRow();
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No se encontraron productos"));
          }
          var docs = snapshot.data!.docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            return (m['hide_online'] as bool?) != true;
          }).toList();
          if (docs.isEmpty) {
            return const Center(child: Text("No se encontraron productos"));
          }
          final ordered = widget.orderedIds;
          if (ordered != null && ordered.isNotEmpty) {
            final indexById = <String, int>{
              for (int i = 0; i < ordered.length; i++) ordered[i]: i,
            };
            const last = 1 << 30;
            docs = docs.toList()
              ..sort((a, b) => (indexById[a.id] ?? last)
                  .compareTo(indexById[b.id] ?? last));
          }

          final entries = expandVariantEntries(docs);
          List<Widget> items =
              entries.map((e) => _buildGridItem(context, e)).toList();
          return ListView(
            scrollDirection: Axis.horizontal,
            children: items,
          );
        },
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, VariantEntry entry) {
    final doc = entry.doc;
    final Map<String, dynamic> data = entry.parentData;

    final String docId = doc.id;
    final String parentName = (data['nombre'] as String?) ?? 'Unnamed';
    final double parentPrice = (data['price'] as num?)?.toDouble() ?? 0.0;
    final String parentImage = (data['image_url'] as String?) ?? '';
    final double parentStock = (data['stock'] as num?)?.toDouble() ?? 0.0;
    final bool isBulk = data['bulk'] as bool? ?? false;
    final String? typeSpecific = data['type_specific'] as String?;

    final String name = parentName;
    final double price = entry.effectivePrice(parentPrice);
    final String imageUrl = entry.effectiveImageUrl(parentImage);
    final double stock = entry.effectiveStock(parentStock);

    final String? variante = entry.isVariant
        ? entry.variantName
        : data['variante'] as String?;

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final bool isGuest = FirebaseAuth.instance.currentUser == null;

    return SizedBox(
      width: 150,
      child: Container(
        margin: const EdgeInsets.fromLTRB(8.0, 8.0, 5.0, 8.0),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 6,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              children: [
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
                  child: SizedBox(
                    height: 136,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                      const ShimmerPlaceholder(height: 80),
                      errorWidget: (context, url, error) =>
                      const Icon(Icons.error, size: 30),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
              child: Column(
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (variante != null && variante.isNotEmpty)
                    Text(
                      variante,
                      style: TextStyle(
                          color: textColor.withValues(alpha: 0.8),
                          fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: isGuest ? 6.0 : 0.0,
                      sigmaY: isGuest ? 6.0 : 0.0,
                    ),
                    child: Text(
                      _formatPrice(price),
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                  Text(
                    typeSpecific ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding:
              const EdgeInsets.only(left: 6.0, right: 6.0, bottom: 6.0),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: _AddToCartButton(
                  key: ValueKey('home-grid-${entry.lineKey}'),
                  data: {
                    'docId': docId,
                    'nombre': name,
                    'price': price,
                    'image_url': imageUrl,
                    'bulk': isBulk,
                    'stock': stock,
                    'type_specific': typeSpecific,
                    'variante': variante,
                    if (entry.isVariant) 'variantKey': entry.variantKey,
                    if (entry.isVariant) 'variantName': entry.variantName,
                  },
                  textColor: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    return '\$${(price as num).toStringAsFixed(2)}';
  }
}

class _AddToCartButton extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color textColor;

  const _AddToCartButton(
      {super.key, required this.data, required this.textColor});

  @override
  _AddToCartButtonState createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<_AddToCartButton> {
  bool _showSwitchTile = false;
  bool _showAgregadoButton = false;
  bool _pendingCommit = false;
  double _quantity = 1;
  Timer? _timer;
  late double stock;
  CartProvider? cartProvider;

  String? _lineId() {
    final docId = widget.data['docId'] as String?;
    if (docId == null) return null;
    final variantKey = widget.data['variantKey'] as String?;
    return buildCartLineId(docId, variantKey);
  }

  @override
  void initState() {
    super.initState();
    _initializeCartState();

    cartProvider = Provider.of<CartProvider>(context, listen: false);
    cartProvider!.addListener(_checkCartState);

    stock = widget.data['stock'] as double? ?? 0.0;
  }

  void _initializeCartState() {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final lineId = _lineId();

    if (lineId != null) {
      final cartItem = cartProvider.getItem(lineId);

      if (cartItem != null) {
        setState(() {
          _quantity = cartItem.quantity;
          _showSwitchTile = true;
          _showAgregadoButton = true;
        });
      }
    }
  }

  void _checkCartState() {
    if (!mounted) return;

    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final lineId = _lineId();

    if (lineId != null) {
      final cartItem = cartProvider.getItem(lineId);

      if (cartItem != null && cartItem.quantity > 0) {
        setState(() {
          _quantity = cartItem.quantity;
          if (!_pendingCommit) {
            _showSwitchTile = true;
            _showAgregadoButton = true;
          }
        });
      } else {
        setState(() {
          _showSwitchTile = false;
          _showAgregadoButton = false;
          _pendingCommit = false;
        });
      }
    }
  }

  void _onAddToCartPressed() {
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.push(context, customPageRoute(const LoginPage()));
      return;
    }

    if (stock == 0) {
      return;
    }

    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    final String? docId = widget.data['docId'] as String?;
    final String? name = widget.data['nombre'] as String?;
    final double? price = widget.data['price'] as double?;
    final String? imageUrl = widget.data['image_url'] as String?;
    final bool isBulk = widget.data['bulk'] as bool? ?? false;
    final String? typeSpecific = widget.data['type_specific'];
    final String? variante = widget.data['variante'];
    final String? variantKey = widget.data['variantKey'] as String?;
    final String? variantName = widget.data['variantName'] as String?;

    if (docId != null && name != null && price != null && imageUrl != null) {
      if (isBulk) {
        _showBulkOrderDialog();
      } else {
        setState(() {
          _showSwitchTile = true;
          _quantity = 1;
          _showAgregadoButton = false;
          _pendingCommit = true;
        });

        _commitToCart(docId, name, price, imageUrl, cartProvider, isBulk,
            typeSpecific, variante, variantKey, variantName);
        _resetAndStartTimer();
      }
    }
  }

  void _commitToCart(
      String docId,
      String name,
      double price,
      String imageUrl,
      CartProvider cartProvider,
      bool isBulk,
      String? typeSpecific,
      String? variante,
      String? variantKey,
      String? variantName) {
    if (_quantity > 0) {
      cartProvider.setItem(
        docId,
        name,
        price,
        imageUrl,
        _quantity,
        isBulk: isBulk,
        stock: stock,
        typeSpecific: typeSpecific,
        variante: variante,
        variantKey: variantKey,
        variantName: variantName,
      );
    } else {
      cartProvider.removeItemCompletely(buildCartLineId(docId, variantKey));
    }
  }

  void _resetAndStartTimer() {
    _timer?.cancel();

    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _pendingCommit = false;
          _showSwitchTile = false;
          _showAgregadoButton = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    cartProvider?.removeListener(_checkCartState);
    super.dispose();
  }

  void _incrementQuantity() {
    if (_quantity < stock) {
      setState(() {
        _quantity++;
        _pendingCommit = true;
      });

      final String? docId = widget.data['docId'] as String?;
      final String? name = widget.data['nombre'] as String?;
      final double? price = widget.data['price'] as double?;
      final String? imageUrl = widget.data['image_url'] as String?;
      final bool isBulk = widget.data['bulk'] as bool? ?? false;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final String? typeSpecific = widget.data['type_specific'];
      final String? variante = widget.data['variante'];
      final String? variantKey = widget.data['variantKey'] as String?;
      final String? variantName = widget.data['variantName'] as String?;

      _commitToCart(docId!, name!, price!, imageUrl!, cartProvider, isBulk,
          typeSpecific, variante, variantKey, variantName);
      _resetAndStartTimer();
    }
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
        _pendingCommit = true;
      });

      final String? docId = widget.data['docId'] as String?;
      final String? name = widget.data['nombre'] as String?;
      final double? price = widget.data['price'] as double?;
      final String? imageUrl = widget.data['image_url'] as String?;
      final bool isBulk = widget.data['bulk'] as bool? ?? false;
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      final String? typeSpecific = widget.data['type_specific'];
      final String? variante = widget.data['variante'];
      final String? variantKey = widget.data['variantKey'] as String?;
      final String? variantName = widget.data['variantName'] as String?;

      _commitToCart(docId!, name!, price!, imageUrl!, cartProvider, isBulk,
          typeSpecific, variante, variantKey, variantName);
      _resetAndStartTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (stock == 0) {
      return ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          minimumSize: const Size(double.infinity, 36),
          maximumSize: const Size(double.infinity, 36),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text('Agotado', style: TextStyle(color: widget.textColor)),
      );
    }

    if (_showAgregadoButton) {
      return ElevatedButton(
        onPressed: () {
          setState(() {
            _showSwitchTile = true;
            _showAgregadoButton = false;
            if (widget.data['bulk'] == true) {
              _showBulkOrderDialog(prefill: true);
            }
          });
        },
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          minimumSize: const Size(double.infinity, 36),
          maximumSize: const Size(double.infinity, 36),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text('Agregado ($_quantity)',
            style: TextStyle(color: widget.textColor)),
      );
    } else if (_showSwitchTile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _quantity > 1 ? _decrementQuantity : null,
              ),
              Text('$_quantity', style: TextStyle(color: widget.textColor)),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _incrementQuantity,
              ),
            ],
          ),
        ],
      );
    } else {
      return ElevatedButton.icon(
        onPressed: _onAddToCartPressed,
        icon: const Icon(Icons.shopping_cart, size: 16),
        label: const Text('Agregar'),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          minimumSize: const Size(double.infinity, 36),
          maximumSize: const Size(double.infinity, 36),
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }
  }

  void _showBulkOrderDialog({bool prefill = false}) {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);
    final pricePerKilo = (widget.data['price'] as num?)?.toDouble() ?? 0.0;
    final cartItem = cartProvider.getItem(widget.data['docId']);
    // Original behavior: prefill is computed first, but the cart-item value
    // always overrides it (matches pre-refactor logic).
    final double initialKilos = cartItem?.quantity ??
        (prefill && _quantity > 0 ? _quantity.toDouble() : 0.0);

    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: _BulkOrderDialog(
            imageUrl: widget.data['image_url'] ?? '',
            nombre: widget.data['nombre'] ?? 'Unnamed',
            variante: widget.data['variante'] ?? 'No variant',
            priceLabel: _formatPrice(widget.data['price']),
            pricePerKilo: pricePerKilo,
            initialKilos: initialKilos,
            stock: stock,
            onConfirm: (kilos) {
              Navigator.of(context).pop();
              if (widget.data['docId'] != null &&
                  widget.data['nombre'] != null) {
                cartProvider.setItem(
                  widget.data['docId'],
                  widget.data['nombre'],
                  widget.data['price'],
                  widget.data['image_url'] ?? '/images/placeholder.png',
                  kilos,
                  isBulk: true,
                  stock: stock,
                  typeSpecific: widget.data['type_specific'],
                  variante: widget.data['variante'],
                  variantKey: widget.data['variantKey'] as String?,
                  variantName: widget.data['variantName'] as String?,
                );
              }
              if (kDebugMode) {
                print('Bulk order set: $kilos kg');
              }
            },
          ),
        );
      },
    );
  }

  String _formatPrice(dynamic price) {
    if (price == null) return 'N/A';
    return '\$${(price as num).toStringAsFixed(2)}';
  }
}

/// Bulk-order dialog body. Owns its own FocusNode + TextEditingController
/// instances so they get disposed when the dialog closes (the previous
/// inline implementation leaked both nodes and their listeners every time
/// the dialog opened).
class _BulkOrderDialog extends StatefulWidget {
  final String imageUrl;
  final String nombre;
  final String variante;
  final String priceLabel;
  final double pricePerKilo;
  final double initialKilos;
  final double stock;
  final ValueChanged<double> onConfirm;

  const _BulkOrderDialog({
    required this.imageUrl,
    required this.nombre,
    required this.variante,
    required this.priceLabel,
    required this.pricePerKilo,
    required this.initialKilos,
    required this.stock,
    required this.onConfirm,
  });

  @override
  State<_BulkOrderDialog> createState() => _BulkOrderDialogState();
}

class _BulkOrderDialogState extends State<_BulkOrderDialog> {
  final TextEditingController pesosController = TextEditingController();
  final TextEditingController kilosController = TextEditingController();
  final FocusNode pesosFocusNode = FocusNode();
  final FocusNode kilosFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    kilosController.text = widget.initialKilos.toStringAsFixed(3);
    pesosController.text =
    '\$${(widget.initialKilos * widget.pricePerKilo).toStringAsFixed(2)}';

    pesosFocusNode.addListener(_handlePesosFocus);
    kilosFocusNode.addListener(_handleKilosFocus);
  }

  void _handlePesosFocus() {
    if (!pesosFocusNode.hasFocus) {
      final pesos =
      double.tryParse(pesosController.text.replaceAll('\$', ''));
      if (pesos != null) {
        kilosController.text =
            (pesos / widget.pricePerKilo).toStringAsFixed(3);
        pesosController.text = '\$${pesos.toStringAsFixed(2)}';
      }
    }
  }

  void _handleKilosFocus() {
    if (!kilosFocusNode.hasFocus) {
      final kilos = double.tryParse(kilosController.text);
      if (kilos != null) {
        pesosController.text =
        '\$${(kilos * widget.pricePerKilo).toStringAsFixed(2)}';
      }
    }
  }

  @override
  void dispose() {
    pesosFocusNode.removeListener(_handlePesosFocus);
    kilosFocusNode.removeListener(_handleKilosFocus);
    pesosFocusNode.dispose();
    kilosFocusNode.dispose();
    pesosController.dispose();
    kilosController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Center(child: Text("Producto a Granel")),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: CachedNetworkImage(
                    imageUrl: widget.imageUrl,
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                    placeholder: (context, url) =>
                    const ShimmerPlaceholder(width: 50, height: 50),
                    errorWidget: (context, url, error) =>
                    const Icon(Icons.error),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.nombre,
                      style:
                      const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(widget.variante),
                    Text(
                      widget.priceLabel,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.justify,
              text: const TextSpan(
                style: TextStyle(color: Colors.black),
                children: [
                  TextSpan(
                    text:
                    "Este producto se vende a granel, por favor indique la cantidad que desea recibir.\n",
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Valor en pesos',
                style: TextStyle(color: Colors.black),
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: pesosController,
                    keyboardType: TextInputType.number,
                    focusNode: pesosFocusNode,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  flex: 1,
                  child: Text(
                    'MXN',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Peso en kilo',
                style: TextStyle(color: Colors.black),
              ),
            ),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: kilosController,
                    keyboardType: TextInputType.number,
                    focusNode: kilosFocusNode,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  flex: 1,
                  child: Text(
                    'kg',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.justify,
              text: const TextSpan(
                style: TextStyle(color: Colors.black),
                children: [
                  TextSpan(
                    text:
                    "\n*Tenga en cuenta que la cantidad recibida puede variar ligeramente.",
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final kilos = double.tryParse(kilosController.text) ?? 0.0;
            if (kilos > widget.stock) {
              return;
            }
            widget.onConfirm(kilos);
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
// (_TermPhase removed: the boot sequence is the only phase now.)

class _ArcadeLaunchPage extends StatefulWidget {
  final String userId;
  final DocumentReference rewardsDocRef;
  final double currentSaldo;

  const _ArcadeLaunchPage({
    required this.userId,
    required this.rewardsDocRef,
    required this.currentSaldo,
  });

  @override
  State<_ArcadeLaunchPage> createState() => _ArcadeLaunchPageState();
}

class _ArcadeLaunchPageState extends State<_ArcadeLaunchPage> {
  final List<String> _visibleLines = [];
  Timer? _lineTimer;
  final ScrollController _scrollCtrl = ScrollController();

  static const _bootLines = [
    '',
    ' ╔══════════════════════════════════╗',
    ' ║   ARCADE OS  v2.4  [2026-03-09]  ║',
    ' ╚══════════════════════════════════╝',
    '',
    ' CPU: MC68000 @ 8 MHz    RAM: 512 KB',
    ' BIOS: 1.0.4              ROM: OK',
    '',
    r' C:\> boot.bat',
    '',
    ' Checking display adapter ....... [ OK ]',
    ' Loading ROM bank 0x0000 ........ [ OK ]',
    ' Input controller check ......... [ OK ]',
    ' Mounting /arcade/fs ............ [ OK ]',
    ' Scoreboard sync ................ [ OK ]',
    ' Allocating framebuffer ......... [ OK ]',
    ' Audio subsystem ................ [ OK ]',
    '',
    r' C:\> authenticate --auto',
    '',
    ' [OK] JUGADOR RECONOCIDO — ACCESO CONCEDIDO',
  ];

  // The old "hacker" phase (fake kernel exploit, "SISTEMA COMPROMETIDO",
  // "DATOS EXFILTRADOS: 2.4 GB", "HUELLAS BORRADAS") was removed. It was
  // meant as a joke, but this app holds wallets and saved cards — a customer
  // has no way to tell a staged breach notice from a real one.

  @override
  void initState() {
    super.initState();
    _startBootLines();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  // No gate anymore: the boot sequence rolls straight into the arcade.
  void _startBootLines() {
    int idx = 0;
    _lineTimer = Timer.periodic(const Duration(milliseconds: 90), (t) {
      if (!mounted) { t.cancel(); return; }
      if (idx < _bootLines.length) {
        setState(() => _visibleLines.add(_bootLines[idx]));
        _scrollToBottom();
        idx++;
      } else {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 600), _launchArcade);
      }
    });
  }

  void _launchArcade() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => ArcadeCenterScreen(
          userId: widget.userId,
          rewardsDocRef: widget.rewardsDocRef,
          currentSaldo: widget.currentSaldo,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  void dispose() {
    _lineTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF010D01),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _CrtScanlinePainter())),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                return SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: double.infinity, minHeight: constraints.maxHeight - 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._visibleLines.map((l) => _TermLine(text: l)),
                        const _BlinkCursor(),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}

class _TermLine extends StatelessWidget {
  final String text;
  const _TermLine({required this.text});

  @override
  Widget build(BuildContext context) {
    // The red "danger" styling went out with the fake-breach lines it used to
    // colour; only the ordinary boot sequence renders here now.
    final isBanner  = text.contains('╔') || text.contains('║') || text.contains('╚')
        || text.contains('██') || text.contains('***');
    final isCmd     = text.trimLeft().startsWith(r'C:\>') || text.trimLeft().startsWith('[>]');
    final isEmpty   = text.trim().isEmpty;

    final Color color;
    final FontWeight weight;
    final List<Shadow> shadows;

    if (isBanner) {
      color   = const Color(0xFF00FF88);
      weight  = FontWeight.bold;
      shadows = const [Shadow(color: Color(0xFF00FF88), blurRadius: 14), Shadow(color: Color(0xFF00FF88), blurRadius: 5)];
    } else if (isCmd) {
      color   = const Color(0xFF88FFBB);
      weight  = FontWeight.bold;
      shadows = const [Shadow(color: Color(0xFF00FF88), blurRadius: 8)];
    } else {
      color   = const Color(0xFF1EBB42);
      weight  = FontWeight.normal;
      shadows = const [Shadow(color: Color(0xFF00AA33), blurRadius: 4)];
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isEmpty ? 4 : 1.5),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontFamily: 'monospace',
          fontWeight: weight,
          letterSpacing: 0.6,
          height: 1.35,
          shadows: shadows,
        ),
      ),
    );
  }
}

class _BlinkCursor extends StatefulWidget {
  const _BlinkCursor();
  @override
  State<_BlinkCursor> createState() => _BlinkCursorState();
}

class _BlinkCursorState extends State<_BlinkCursor> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Text(
        _ctrl.value > 0.5 ? '█' : ' ',
        style: const TextStyle(
          color: Color(0xFF00FF88),
          fontSize: 12,
          fontFamily: 'monospace',
          shadows: [Shadow(color: Color(0xFF00FF88), blurRadius: 8)],
        ),
      ),
    );
  }
}

class _CrtScanlinePainter extends CustomPainter {
  const _CrtScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1.0;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_CrtScanlinePainter _) => false;
}
