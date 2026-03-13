import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/auth_service.dart';
import '../main.dart';

// ─── Data ─────────────────────────────────────────────────────────────────────
const _categories = [
  'Flooding',
  'Fire',
  'Medical Emergency',
  'Infrastructure Damage',
];

const _severityLevels = ['High', 'Medium', 'Low'];

const _severityDescriptions = {
  'High': 'Life-threatening or immediate danger to persons/property.',
  'Medium': 'Serious issue that needs response but no immediate danger.',
  'Low': 'Minor concern addressable in routine operations.',
};

// ─── Screen ───────────────────────────────────────────────────────────────────
class SubmitReportScreen extends StatefulWidget {
  const SubmitReportScreen({super.key});

  @override
  State<SubmitReportScreen> createState() => _SubmitReportScreenState();
}

class _SubmitReportScreenState extends State<SubmitReportScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  late AnimationController _enterCtrl;
  late AnimationController _scanCtrl;
  late List<Animation<Offset>> _slideAnims;
  late List<Animation<double>> _fadeAnims;
  late Animation<double> _scan;

  String? _selectedCategory;
  String? _selectedSeverity;
  bool _submitting = false;

  // Location
  double? _pinnedLat;
  double? _pinnedLng;
  bool _gettingLocation = false;

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _slideAnims = List.generate(
      7,
      (i) =>
          Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
            CurvedAnimation(
              parent: _enterCtrl,
              curve: Interval(
                i * 0.08,
                0.6 + i * 0.07,
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
    );
    _fadeAnims = List.generate(
      7,
      (i) => Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _enterCtrl,
          curve: Interval(i * 0.08, 0.6 + i * 0.07, curve: Curves.easeOut),
        ),
      ),
    );
    _scan = CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _locationCtrl.dispose();
    _enterCtrl.dispose();
    _scanCtrl.dispose();
    super.dispose();
  }

  Widget _animated(int i, Widget child) => SlideTransition(
    position: _slideAnims[i],
    child: FadeTransition(opacity: _fadeAnims[i], child: child),
  );

  Color _severityColor(String s) => switch (s) {
    'High' => AppColors.red,
    'Medium' => AppColors.amber,
    _ => AppColors.green,
  };

  IconData _severityIcon(String s) => switch (s) {
    'High' => Icons.warning_rounded,
    'Medium' => Icons.report_problem_outlined,
    _ => Icons.check_circle_outline,
  };

  IconData _categoryIcon(String c) => switch (c) {
    'Flooding' => Icons.water_rounded,
    'Fire' => Icons.local_fire_department_rounded,
    'Medical Emergency' => Icons.medical_services_outlined,
    'Infrastructure Damage' => Icons.construction_rounded,
    _ => Icons.report_outlined,
  };

  // ── LOCATION ──────────────────────────────────────────────────────────────
  Future<void> _getCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('LOCATION SERVICES ARE DISABLED. ENABLE GPS AND TRY AGAIN.');
        return;
      }

      // Check/request permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('LOCATION PERMISSION DENIED');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showError(
          'LOCATION PERMISSION PERMANENTLY DENIED. ENABLE IN DEVICE SETTINGS.',
        );
        return;
      }

      Position? position;

      // ── Step 1: Try last known position first (instant, no timeout risk) ──
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      // ── Step 2: If no last known, try medium accuracy with short timeout ──
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (_) {}
      }

      // ── Step 3: Final fallback — low accuracy, longer timeout ──
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 20),
          ),
        );
      }

      setState(() {
        _pinnedLat = position!.latitude;
        _pinnedLng = position.longitude;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.void_,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: AppColors.green, width: 1),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: AppColors.green,
                size: 14,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'LOCATION PINNED: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontFamily: 'IBMPlexMono',
                    fontSize: 9,
                    color: AppColors.green,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // ── Friendly timeout message instead of raw exception ──
      final msg = e.toString().toLowerCase();
      if (msg.contains('timeout') || msg.contains('timeoutexception')) {
        _showError(
          'GPS SIGNAL TIMEOUT — MOVE TO AN OPEN AREA OR ENABLE WIFI/MOBILE DATA TO ASSIST LOCATION.',
        );
      } else {
        _showError('LOCATION ERROR: ${e.toString().toUpperCase()}');
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  void _clearLocation() {
    setState(() {
      _pinnedLat = null;
      _pinnedLng = null;
    });
  }

  // ── SUBMIT ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      _showError('SELECT A CATEGORY');
      return;
    }
    if (_selectedSeverity == null) {
      _showError('SELECT A SEVERITY LEVEL');
      return;
    }

    setState(() => _submitting = true);
    try {
      // Cross-field: need at least GPS coords OR a description
      final hasDesc = _descriptionCtrl.text.trim().isNotEmpty;
      final hasGps = _pinnedLat != null;
      if (!hasGps && !hasDesc) {
        _showError('PIN A GPS LOCATION OR ENTER AN INCIDENT DESCRIPTION');
        setState(() => _submitting = false);
        return;
      }

      final user = _supabase.auth.currentUser;
      final userData = AuthService.getUserData();

      await _supabase.from('reports').insert({
        'user_id': user?.id,
        'description': _descriptionCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'lat': _pinnedLat,
        'lng': _pinnedLng,
        'category': _selectedCategory,
        'severity': _selectedSeverity,
        'status': 'Pending',
        'barangay': userData?['barangay'] ?? 'Del Rosario',
      });

      if (!mounted) return;
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      _showError('TRANSMISSION FAILED — ${e.toString().toUpperCase()}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.void_,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: AppColors.red.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.red, size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'IBMPlexMono',
                  fontSize: 10,
                  color: AppColors.red,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccess() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.ink.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.void_,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CustomPaint(painter: _GridPainter()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.green.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.green.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.green,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'REPORT TRANSMITTED',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_pinnedLat != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.electric.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: AppColors.electric.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 10,
                              color: AppColors.electric,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'GPS: ${_pinnedLat!.toStringAsFixed(4)}, ${_pinnedLng!.toStringAsFixed(4)}',
                              style: const TextStyle(
                                fontFamily: 'IBMPlexMono',
                                fontSize: 9,
                                color: AppColors.electric,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: AppColors.green.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'STATUS: PENDING TRIAGE',
                          style: TextStyle(
                            fontFamily: 'IBMPlexMono',
                            fontSize: 9,
                            color: AppColors.green,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your report has been received and is now pending triage classification. Barangay officials will be notified immediately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'IBMPlexMono',
                      fontSize: 10,
                      color: AppColors.textSecondary,
                      height: 1.7,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _TacticalButton(
                      label: 'BACK TO DASHBOARD',
                      icon: Icons.arrow_back_rounded,
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                      },
                      primary: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.campaign_outlined, size: 18, color: AppColors.electric),
            SizedBox(width: 8),
            Text(
              'SUBMIT INCIDENT',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          CustomPaint(
            painter: _GridPainter(),
            size: MediaQuery.of(context).size,
          ),
          AnimatedBuilder(
            animation: _scan,
            builder: (_, __) {
              final h = MediaQuery.of(context).size.height;
              return Positioned(
                top: _scan.value * h,
                left: 0,
                right: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.electric.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const _CornerAccents(),
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header banner ──────────────────────────────────
                  _animated(
                    0,
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.electric.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.electric.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.electric.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.electric.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.campaign_outlined,
                              color: AppColors.electric,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'FILE A CITIZEN REPORT',
                                  style: TextStyle(
                                    fontFamily: 'Rajdhani',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    letterSpacing: 2,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Reports are forwarded to barangay officials immediately upon submission.',
                                  style: TextStyle(
                                    fontFamily: 'IBMPlexMono',
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                    height: 1.6,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Category ───────────────────────────────────────
                  _animated(1, _SectionHeader('INCIDENT CATEGORY')),
                  const SizedBox(height: 14),
                  _animated(
                    1,
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.7,
                      children: _categories.map((cat) {
                        final selected = _selectedCategory == cat;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.electric.withValues(alpha: 0.1)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: selected
                                    ? AppColors.electric
                                    : AppColors.border,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _categoryIcon(cat),
                                  size: 16,
                                  color: selected
                                      ? AppColors.electric
                                      : AppColors.textDim,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    cat.toUpperCase(),
                                    style: TextStyle(
                                      fontFamily: 'IBMPlexMono',
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? AppColors.electric
                                          : AppColors.textSecondary,
                                      letterSpacing: 0.6,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Severity ───────────────────────────────────────
                  _animated(2, _SectionHeader('SEVERITY LEVEL')),
                  const SizedBox(height: 4),
                  _animated(
                    2,
                    const Padding(
                      padding: EdgeInsets.only(left: 11, bottom: 14),
                      child: Text(
                        'Select the severity that best describes the situation.',
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          fontSize: 10,
                          color: AppColors.textDim,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  _animated(
                    2,
                    Column(
                      children: _severityLevels.map((sev) {
                        final selected = _selectedSeverity == sev;
                        final color = _severityColor(sev);
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSeverity = sev),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withValues(alpha: 0.07)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: selected ? color : AppColors.border,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Icon(
                                    _severityIcon(sev),
                                    color: color,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sev.toUpperCase(),
                                        style: TextStyle(
                                          fontFamily: 'Rajdhani',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: selected
                                              ? color
                                              : AppColors.textPrimary,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                      Text(
                                        _severityDescriptions[sev]!,
                                        style: const TextStyle(
                                          fontFamily: 'IBMPlexMono',
                                          fontSize: 9,
                                          color: AppColors.textDim,
                                          height: 1.5,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_rounded,
                                    color: color,
                                    size: 16,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Location ───────────────────────────────────────
                  _animated(3, _SectionHeader('LOCATION')),
                  const SizedBox(height: 14),

                  // GPS Pin button
                  _animated(
                    3,
                    _pinnedLat != null
                        ? Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.green.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.green.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.green.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: AppColors.green,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'GPS LOCATION PINNED',
                                        style: TextStyle(
                                          fontFamily: 'Rajdhani',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.green,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      Text(
                                        '${_pinnedLat!.toStringAsFixed(6)}, ${_pinnedLng!.toStringAsFixed(6)}',
                                        style: const TextStyle(
                                          fontFamily: 'IBMPlexMono',
                                          fontSize: 9,
                                          color: AppColors.textSecondary,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _clearLocation,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.red.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: AppColors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: _gettingLocation
                                ? null
                                : _getCurrentLocation,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppColors.border,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_gettingLocation)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        color: AppColors.electric,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.my_location_rounded,
                                      size: 16,
                                      color: AppColors.electric,
                                    ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _gettingLocation
                                        ? 'ACQUIRING GPS SIGNAL...'
                                        : 'PIN MY CURRENT LOCATION',
                                    style: const TextStyle(
                                      fontFamily: 'Rajdhani',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.electric,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),

                  _animated(
                    3,
                    _TacticalTextField(
                      controller: _locationCtrl,
                      label:
                          'LOCATION DESCRIPTION${_pinnedLat != null ? ' (OPTIONAL)' : ''}',
                      hint: _pinnedLat != null
                          ? 'e.g. Purok 3, near the bridge (optional)'
                          : 'e.g. Purok 3, near the bridge',
                      icon: Icons.location_on_outlined,
                      validator: (v) {
                        if (_pinnedLat != null)
                          return null; // GPS pinned — text optional
                        if (v == null || v.trim().isEmpty) {
                          return 'PIN GPS LOCATION OR ENTER A LOCATION DESCRIPTION';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Text(
                      'PIN YOUR GPS LOCATION ABOVE AND/OR DESCRIBE THE LOCATION BELOW.',
                      style: TextStyle(
                        fontFamily: 'IBMPlexMono',
                        fontSize: 8,
                        color: AppColors.textDim,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Description ────────────────────────────────────
                  _animated(4, _SectionHeader('INCIDENT DESCRIPTION')),
                  const SizedBox(height: 4),
                  _animated(
                    4,
                    const Padding(
                      padding: EdgeInsets.only(left: 11, bottom: 14),
                      child: Text(
                        'Describe the incident clearly — who, what, and how many are affected.',
                        style: TextStyle(
                          fontFamily: 'IBMPlexMono',
                          fontSize: 10,
                          color: AppColors.textDim,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  _animated(
                    4,
                    _TacticalTextField(
                      controller: _descriptionCtrl,
                      label:
                          'DESCRIPTION${_pinnedLat != null ? ' (OPTIONAL)' : ''}',
                      hint: _pinnedLat != null
                          ? 'Describe the situation… (optional if GPS pinned)'
                          : 'Describe the situation…',
                      icon: Icons.edit_note_rounded,
                      maxLines: 5,
                      maxLength: 500,
                      validator: (v) {
                        if (_pinnedLat != null) {
                          // GPS pinned — description optional, but if filled must be meaningful
                          if (v != null &&
                              v.trim().isNotEmpty &&
                              v.trim().length < 5) {
                            return 'DESCRIPTION IS TOO SHORT';
                          }
                          return null;
                        }
                        if (v == null || v.trim().isEmpty) {
                          return 'DESCRIPTION IS REQUIRED (OR PIN YOUR GPS LOCATION)';
                        }
                        if (v.trim().length < 10) {
                          return 'DESCRIPTION IS TOO SHORT';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Info notice ────────────────────────────────────
                  _animated(
                    5,
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.blue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Icon(
                              Icons.info_outline_rounded,
                              color: AppColors.blue,
                              size: 14,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'GPS coordinates allow description and location text to be optional. If no GPS is pinned, both fields are required.',
                              style: TextStyle(
                                fontFamily: 'IBMPlexMono',
                                fontSize: 10,
                                color: AppColors.blue,
                                height: 1.6,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Submit ─────────────────────────────────────────
                  _animated(
                    6,
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: _submitting
                          ? Container(
                              decoration: BoxDecoration(
                                color: AppColors.electric.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: AppColors.electric.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: AppColors.electric,
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : _TacticalButton(
                              label: 'TRANSMIT REPORT',
                              icon: Icons.send_rounded,
                              onPressed: _submit,
                              primary: true,
                            ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: AppColors.electric),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }
}

class _TacticalTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final int maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;

  const _TacticalTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'IBMPlexMono',
            fontSize: 9,
            color: AppColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          validator: validator,
          style: const TextStyle(
            fontFamily: 'IBMPlexMono',
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontFamily: 'IBMPlexMono',
              color: AppColors.textDim,
              fontSize: 12,
            ),
            prefixIcon: Icon(icon, size: 16, color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            alignLabelWithHint: true,
            counterStyle: const TextStyle(
              fontFamily: 'IBMPlexMono',
              fontSize: 9,
              color: AppColors.textDim,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 15,
              horizontal: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(
                color: AppColors.electric,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: AppColors.red.withValues(alpha: 0.6),
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: AppColors.red, width: 1.5),
            ),
            errorStyle: const TextStyle(
              fontFamily: 'IBMPlexMono',
              fontSize: 9,
              color: AppColors.red,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _TacticalButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool primary;

  const _TacticalButton({
    required this.label,
    required this.onPressed,
    this.icon,
    required this.primary,
  });

  @override
  State<_TacticalButton> createState() => _TacticalButtonState();
}

class _TacticalButtonState extends State<_TacticalButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: widget.primary
              ? (_pressed ? AppColors.electric : AppColors.electricDim)
              : (_pressed ? AppColors.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.primary ? AppColors.electric : AppColors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(
                widget.icon,
                size: 15,
                color: widget.primary
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: widget.primary
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────────

class _CornerAccents extends StatelessWidget {
  const _CornerAccents();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _CornerPainter(), size: MediaQuery.of(context).size);
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.electric.withValues(alpha: 0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const len = 20.0;
    canvas.drawLine(const Offset(16, 16), const Offset(16 + len, 16), paint);
    canvas.drawLine(const Offset(16, 16), const Offset(16, 16 + len), paint);
    canvas.drawLine(
      Offset(size.width - 16, 16),
      Offset(size.width - 16 - len, 16),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 16, 16),
      Offset(size.width - 16, 16 + len),
      paint,
    );
    canvas.drawLine(
      Offset(16, size.height - 16),
      Offset(16 + len, size.height - 16),
      paint,
    );
    canvas.drawLine(
      Offset(16, size.height - 16),
      Offset(16, size.height - 16 - len),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 16, size.height - 16),
      Offset(size.width - 16 - len, size.height - 16),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - 16, size.height - 16),
      Offset(size.width - 16, size.height - 16 - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.25)
      ..strokeWidth = 0.5;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
