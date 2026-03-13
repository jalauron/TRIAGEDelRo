import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'login.dart';
import 'account_settings.dart';
import '../main.dart';

class _Report {
  final String id;
  final String rawId;
  final String description;
  final String location;
  final double? lat;
  final double? lng;
  final String category;
  final String severity;
  final String status;
  final DateTime submittedAt;

  _Report({
    required this.id,
    required this.rawId,
    required this.description,
    required this.location,
    required this.lat,
    required this.lng,
    required this.category,
    required this.severity,
    required this.status,
    required this.submittedAt,
  });

  factory _Report.fromMap(Map<String, dynamic> m) => _Report(
    id: (m['id'] as String).substring(0, 8).toUpperCase(),
    rawId: m['id'] as String,
    description: m['description'] ?? '',
    location: m['location'] ?? '',
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
    category: m['category'] ?? '',
    severity: m['severity'] ?? '',
    status: m['status'] ?? '',
    submittedAt: DateTime.parse(m['submitted_at']),
  );

  bool get hasCoords => lat != null && lng != null;
  String get coordsLabel =>
      hasCoords ? '${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}' : '';
}

class OfficialDashboard extends StatefulWidget {
  const OfficialDashboard({super.key});
  @override
  State<OfficialDashboard> createState() => _OfficialDashboardState();
}

class _OfficialDashboardState extends State<OfficialDashboard>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  String _username = 'Official';
  String _fullName = '';
  String _position = '';
  List<_Report> _reports = [];
  bool _loadingUser = true;
  bool _loadingReports = true;
  String _filterStatus = 'All';
  final _statuses = ['All', 'Pending', 'Ongoing', 'Resolved'];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadUser();
    _loadReports();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _loadUser() {
    final data = AuthService.getUserData();
    setState(() {
      if (data != null) {
        _username = data['username'] ?? 'Official';
        _fullName = '${data['first_name'] ?? ''} ${data['last_name'] ?? ''}'
            .trim();
        _position = data['position'] ?? '';
      }
      _loadingUser = false;
    });
  }

  Future<void> _loadReports() async {
    setState(() => _loadingReports = true);
    try {
      final data = await _supabase
          .from('reports')
          .select()
          .order('submitted_at', ascending: false)
          .limit(50);
      setState(() {
        _reports = (data as List).map((r) => _Report.fromMap(r)).toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  Future<void> _updateStatus(String reportId, String newStatus) async {
    try {
      await _supabase
          .from('reports')
          .update({'status': newStatus})
          .eq('id', reportId);
      await _loadReports();
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
              Text(
                'STATUS UPDATED TO ${newStatus.toUpperCase()}',
                style: const TextStyle(
                  fontFamily: 'IBMPlexMono',
                  fontSize: 10,
                  color: AppColors.green,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
          content: const Text(
            'UPDATE FAILED',
            style: TextStyle(
              fontFamily: 'IBMPlexMono',
              fontSize: 10,
              color: AppColors.red,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _LogoutDialog(),
    );
    if (confirmed == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
        (_) => false,
      );
    }
  }

  Future<void> _openAccountSettings() async {
    final refreshNeeded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsScreen()),
    );
    if (refreshNeeded == true) _loadUser();
  }

  Color _severityColor(String s) => switch (s) {
    'High' => AppColors.red,
    'Medium' => AppColors.amber,
    _ => AppColors.green,
  };

  Color _statusColor(String s) => switch (s) {
    'Resolved' => AppColors.green,
    'Ongoing' => AppColors.blue,
    _ => AppColors.amber,
  };

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 60) return '${d.inMinutes}M AGO';
    if (d.inHours < 24) return '${d.inHours}H AGO';
    return '${d.inDays}D AGO';
  }

  List<_Report> get _filtered => _filterStatus == 'All'
      ? _reports
      : _reports.where((r) => r.status == _filterStatus).toList();

  int get _pendingCount => _reports.where((r) => r.status == 'Pending').length;
  int get _ongoingCount => _reports.where((r) => r.status == 'Ongoing').length;
  int get _highCount => _reports.where((r) => r.severity == 'High').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        elevation: 0,
        titleSpacing: 20,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CustomPaint(painter: _MiniHexPainter()),
            ),
            const SizedBox(width: 10),
            const Text(
              'TRIAGE DEL ROSARIO',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.amber.withValues(alpha: _pulse.value),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.manage_accounts_outlined,
              size: 20,
              color: AppColors.textSecondary,
            ),
            tooltip: 'Account Settings',
            onPressed: _openAccountSettings,
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_outlined,
              size: 20,
              color: AppColors.textSecondary,
            ),
            tooltip: 'Sign out',
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loadingUser
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.electric,
                strokeWidth: 2,
              ),
            )
          : RefreshIndicator(
              color: AppColors.electric,
              backgroundColor: AppColors.void_,
              onRefresh: _loadReports,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OperatorCard(
                      username: _username,
                      fullName: _fullName,
                      roleLabel: 'BRGY OFFICIAL',
                      roleSubLabel: _position.isNotEmpty
                          ? _position.toUpperCase()
                          : 'BDRRMC OFFICER',
                      roleColor: AppColors.amber,
                      onTap: _openAccountSettings,
                      pulse: _pulse,
                    ),
                    const SizedBox(height: 24),

                    _SectionLabel(
                      label: 'INCIDENT OVERVIEW',
                      tag: 'LAST UPDATED ${_timeAgo(DateTime.now())}',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatTile(
                          label: 'PENDING',
                          value: '$_pendingCount',
                          color: AppColors.amber,
                          icon: Icons.pending_actions_outlined,
                        ),
                        const SizedBox(width: 10),
                        _StatTile(
                          label: 'ONGOING',
                          value: '$_ongoingCount',
                          color: AppColors.blue,
                          icon: Icons.sync_rounded,
                        ),
                        const SizedBox(width: 10),
                        _StatTile(
                          label: 'CRITICAL',
                          value: '$_highCount',
                          color: AppColors.red,
                          icon: Icons.warning_amber_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    _SectionLabel(
                      label: 'ALL INCIDENT REPORTS',
                      tag: '${_filtered.length} RECORDS',
                    ),
                    const SizedBox(height: 12),

                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _statuses.map((s) {
                          final active = _filterStatus == s;
                          return GestureDetector(
                            onTap: () => setState(() => _filterStatus = s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.electric.withValues(alpha: 0.12)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: active
                                      ? AppColors.electric
                                      : AppColors.border,
                                  width: active ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                s.toUpperCase(),
                                style: TextStyle(
                                  fontFamily: 'IBMPlexMono',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? AppColors.electric
                                      : AppColors.textSecondary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _loadingReports
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: CircularProgressIndicator(
                                color: AppColors.electric,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : _filtered.isEmpty
                        ? const _EmptyState()
                        : Column(
                            children: _filtered
                                .map(
                                  (r) => _IncidentCard(
                                    report: r,
                                    severityColor: _severityColor(r.severity),
                                    statusColor: _statusColor(r.status),
                                    timeAgo: _timeAgo(r.submittedAt),
                                    onUpdateStatus: (s) =>
                                        _updateStatus(r.rawId, s),
                                  ),
                                )
                                .toList(),
                          ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? tag;
  const _SectionLabel({required this.label, this.tag});

  @override
  Widget build(BuildContext context) => Row(
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
      const Spacer(),
      if (tag != null)
        Text(
          tag!,
          style: const TextStyle(
            fontFamily: 'IBMPlexMono',
            fontSize: 9,
            color: AppColors.textDim,
            letterSpacing: 1,
          ),
        ),
    ],
  );
}

class _OperatorCard extends StatelessWidget {
  final String username;
  final String fullName;
  final String roleLabel;
  final String roleSubLabel;
  final Color roleColor;
  final VoidCallback onTap;
  final Animation<double> pulse;

  const _OperatorCard({
    required this.username,
    required this.fullName,
    required this.roleLabel,
    required this.roleSubLabel,
    required this.roleColor,
    required this.onTap,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: _AccentCard(
      accentColor: roleColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    painter: _MiniHexPainter(
                      fillColor: AppColors.surface,
                      strokeColor: roleColor,
                    ),
                    size: const Size(48, 48),
                  ),
                  Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'O',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: roleColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$username',
                    style: const TextStyle(
                      fontFamily: 'Rajdhani',
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  if (fullName.isNotEmpty)
                    Text(
                      fullName.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'IBMPlexMono',
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: roleColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    roleLabel,
                    style: TextStyle(
                      fontFamily: 'IBMPlexMono',
                      fontSize: 9,
                      color: roleColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  roleSubLabel,
                  style: const TextStyle(
                    fontFamily: 'IBMPlexMono',
                    fontSize: 8,
                    color: AppColors.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'IBMPlexMono',
              fontSize: 8,
              color: AppColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    decoration: BoxDecoration(
      color: AppColors.void_,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.border),
    ),
    child: const Column(
      children: [
        Icon(Icons.inbox_outlined, size: 28, color: AppColors.textDim),
        SizedBox(height: 16),
        Text(
          'NO REPORTS FOUND',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: AppColors.textPrimary,
            letterSpacing: 2,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'No incident reports match the selected filter.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'IBMPlexMono',
            fontSize: 10,
            color: AppColors.textSecondary,
            height: 1.7,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ),
  );
}

class _IncidentCard extends StatelessWidget {
  final _Report report;
  final Color severityColor;
  final Color statusColor;
  final String timeAgo;
  final void Function(String) onUpdateStatus;

  const _IncidentCard({
    required this.report,
    required this.severityColor,
    required this.statusColor,
    required this.timeAgo,
    required this.onUpdateStatus,
  });

  void _showStatusPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.void_,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 3, height: 14, color: AppColors.electric),
                const SizedBox(width: 8),
                Text(
                  'UPDATE RPT-${report.id}',
                  style: const TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...['Pending', 'Ongoing', 'Resolved'].map(
              (s) => GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  onUpdateStatus(s);
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: report.status == s
                        ? AppColors.electric.withValues(alpha: 0.08)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: report.status == s
                          ? AppColors.electric
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        s.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: report.status == s
                              ? AppColors.electric
                              : AppColors.textPrimary,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      if (report.status == s)
                        const Icon(
                          Icons.check_rounded,
                          color: AppColors.electric,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _AccentCard(
      accentColor: severityColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(
                  label: report.severity.toUpperCase(),
                  color: severityColor,
                ),
                const SizedBox(width: 6),
                _Badge(
                  label: report.category.toUpperCase(),
                  color: AppColors.textDim,
                  filled: false,
                ),
                const Spacer(),
                Text(
                  timeAgo,
                  style: const TextStyle(
                    fontFamily: 'IBMPlexMono',
                    fontSize: 9,
                    color: AppColors.textDim,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              report.description,
              style: const TextStyle(
                fontFamily: 'SourceSans3',
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (report.location.isNotEmpty || report.hasCoords) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 11,
                    color: AppColors.textDim,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      report.hasCoords
                          ? '${report.coordsLabel}${report.location.isNotEmpty ? ' · ${report.location}' : ''}'
                          : report.location,
                      style: const TextStyle(
                        fontFamily: 'IBMPlexMono',
                        fontSize: 9,
                        color: AppColors.textDim,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'RPT-${report.id}',
                  style: const TextStyle(
                    fontFamily: 'IBMPlexMono',
                    fontSize: 9,
                    color: AppColors.textDim,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showStatusPicker(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          report.status.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'IBMPlexMono',
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 11,
                          color: statusColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  const _Badge({required this.label, required this.color, this.filled = true});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? color.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(2),
      border: Border.all(color: color.withValues(alpha: filled ? 0.3 : 0.2)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'IBMPlexMono',
        fontSize: 8,
        fontWeight: FontWeight.w600,
        color: filled ? color : AppColors.textDim,
        letterSpacing: 1,
      ),
    ),
  );
}

// ─── Painters ─────────────────────────────────────────────────────────────────

class _MiniHexPainter extends CustomPainter {
  final Color fillColor;
  final Color strokeColor;
  _MiniHexPainter({
    this.fillColor = AppColors.surface,
    this.strokeColor = AppColors.electric,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 * 0.88;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = (i * 60 - 30) * math.pi / 180;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _AccentCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final Color bgColor;
  final double radius;
  final double accentWidth;

  const _AccentCard({
    required this.child,
    required this.accentColor,
    this.bgColor = AppColors.void_,
    this.radius = 6,
    this.accentWidth = 2,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: child,
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Container(width: accentWidth, color: accentColor),
        ),
      ],
    ),
  );
}

class _LogoutDialog extends StatelessWidget {
  const _LogoutDialog();

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.void_,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 18, color: AppColors.amber),
              const SizedBox(width: 10),
              const Text(
                'CONFIRM SIGN OUT',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Your session will be terminated. Confirm sign out?',
            style: TextStyle(
              fontFamily: 'IBMPlexMono',
              fontSize: 11,
              color: AppColors.textSecondary,
              height: 1.6,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red.withValues(alpha: 0.15),
                    foregroundColor: AppColors.red,
                    side: BorderSide(
                      color: AppColors.red.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    minimumSize: const Size.fromHeight(44),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'SIGN OUT',
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
