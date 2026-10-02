import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _ink = Color(0xFF172033);
const _muted = Color(0xFF667085);
const _accent = Color(0xFF2457D6);
const _surface = Color(0xFFF7F9FC);

class AdminSession {
  const AdminSession({
    required this.accessToken,
    required this.refreshToken,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final String email;
}

class AdminApi {
  AdminApi({required this.baseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
            ),
          );

  final String baseUrl;
  final Dio _dio;
  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;

  Future<AdminSession> signIn(String email, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    final body = response.data!;
    final tokens = body['tokens'] as Map<String, dynamic>?;
    final user = body['user'] as Map<String, dynamic>?;
    final roles = (user?['roles'] as List<dynamic>? ?? const [])
        .map((role) => role.toString())
        .toSet();
    if (tokens == null || user == null) {
      throw const FormatException('The server returned an incomplete sign-in.');
    }
    if (!roles.contains('admin')) {
      throw const AdminAccessException();
    }
    final session = AdminSession(
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
      email: user['email'] as String,
    );
    _accessToken = session.accessToken;
    _refreshToken = session.refreshToken;
    return session;
  }

  Future<AdminPage<AdminUser>> users() async {
    final response = await _get('/v1/admin/users');
    return AdminPage.fromJson(response, AdminUser.fromJson);
  }

  Future<AdminPage<AuditEvent>> auditEvents() async {
    final response = await _get('/v1/admin/audit-events');
    return AdminPage.fromJson(response, AuditEvent.fromJson);
  }

  Future<AdminPage<AdminCompetency>> competencies() async {
    final response = await _get('/v1/admin/competencies');
    return AdminPage.fromJson(response, AdminCompetency.fromJson);
  }

  Future<void> reviewCompetency(
    AdminCompetency competency,
    String status, {
    String? reason,
  }) async {
    await _authorized(
      () => _dio.patch<Map<String, dynamic>>(
      '/v1/admin/competencies/${competency.id}/review',
      data: {
        'status': status,
        ...?reason == null ? null : {'rejection_reason': reason},
      },
        options: _authOptions(),
      ),
    );
  }

  Future<AdminPage<AdminTutorStanding>> tutorStandings() async {
    final response = await _get('/v1/admin/tutor-standings');
    return AdminPage.fromJson(response, AdminTutorStanding.fromJson);
  }

  void signOut() {
    _accessToken = null;
    _refreshToken = null;
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _authorized(
      () => _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: const {'offset': 0, 'limit': 50},
        options: _authOptions(),
      ),
    );
    return response.data!;
  }

  Options _authOptions() =>
      Options(headers: {'Authorization': 'Bearer $_accessToken'});

  Future<Response<T>> _authorized<T>(
    Future<Response<T>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (error) {
      if (error.response?.statusCode != 401 || !await _refresh()) {
        rethrow;
      }
      return request();
    }
  }

  Future<bool> _refresh() async {
    final token = _refreshToken;
    if (token == null) return false;
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _refreshInFlight = () async {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/auth/refresh',
          data: {'refresh_token': token},
        );
        final tokens = response.data?['tokens'] as Map<String, dynamic>?;
        final access = tokens?['access_token'];
        final refresh = tokens?['refresh_token'];
        if (access is! String || refresh is! String) {
          signOut();
          return false;
        }
        _accessToken = access;
        _refreshToken = refresh;
        return true;
      } on DioException {
        signOut();
        return false;
      } finally {
        _refreshInFlight = null;
      }
    }();
    return future;
  }
}

class AdminAccessException implements Exception {
  const AdminAccessException();
}

class AdminPage<T> {
  const AdminPage({required this.items, required this.total});

  factory AdminPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    return AdminPage(
      items: (json['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(parse)
          .toList(),
      total: json['total'] as int,
    );
  }

  final List<T> items;
  final int total;
}

class AdminUser {
  const AdminUser({
    required this.email,
    required this.name,
    required this.roles,
    required this.isActive,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    email: json['email'] as String,
    name: json['full_name'] as String?,
    roles: (json['roles'] as List<dynamic>).cast<String>(),
    isActive: json['is_active'] as bool,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String email;
  final String? name;
  final List<String> roles;
  final bool isActive;
  final DateTime createdAt;
}

class AuditEvent {
  const AuditEvent({
    required this.action,
    required this.targetType,
    required this.createdAt,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
    action: json['action'] as String,
    targetType: json['target_type'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String action;
  final String targetType;
  final DateTime createdAt;
}

class AdminCompetency {
  const AdminCompetency({
    required this.id,
    required this.email,
    required this.name,
    required this.unit,
    required this.grade,
    required this.status,
    required this.evidence,
  });

  factory AdminCompetency.fromJson(Map<String, dynamic> json) =>
      AdminCompetency(
        id: json['id'] as String,
        email: json['user_email'] as String,
        name: json['user_name'] as String?,
        unit: '${json['course_unit_code']} - ${json['course_unit_name']}',
        grade: json['grade_points'] as String,
        status: json['status'] as String,
        evidence: json['evidence_reference'] as String?,
      );

  final String id;
  final String email;
  final String? name;
  final String unit;
  final String grade;
  final String status;
  final String? evidence;
}

class AdminTutorStanding {
  const AdminTutorStanding({
    required this.email,
    required this.name,
    required this.standing,
    required this.sessions,
    required this.rating,
  });

  factory AdminTutorStanding.fromJson(Map<String, dynamic> json) =>
      AdminTutorStanding(
        email: json['user_email'] as String,
        name: json['user_name'] as String?,
        standing: json['standing'] as String,
        sessions: json['completed_sessions'] as int,
        rating: json['average_rating'] as String?,
      );

  final String email;
  final String? name;
  final String standing;
  final int sessions;
  final String? rating;
}

final apiProvider = Provider<AdminApi>(
  (ref) => AdminApi(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8000',
    ),
  ),
);

final sessionProvider = NotifierProvider<SessionController, AdminSession?>(
  SessionController.new,
);

class SessionController extends Notifier<AdminSession?> {
  @override
  AdminSession? build() => null;

  void signedIn(AdminSession session) => state = session;

  void signedOut() => state = null;
}

void main() => runApp(const ProviderScope(child: AdminApp()));

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'PeerPass Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _accent),
        scaffoldBackgroundColor: _surface,
        fontFamily: 'Arial',
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: session == null ? const SignInPage() : AdminShell(session: session),
    );
  }
}

class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_email.text.contains('@') || _password.text.isEmpty) {
      setState(() => _error = 'Enter an administrator email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref
          .read(apiProvider)
          .signIn(_email.text.trim(), _password.text);
      ref.read(sessionProvider.notifier).signedIn(session);
    } on AdminAccessException {
      setState(
        () => _error = 'This account is not provisioned for admin access.',
      );
    } on DioException catch (error) {
      final detail = error.response?.data;
      setState(
        () => _error =
            detail is Map<String, dynamic> && detail['detail'] is String
            ? detail['detail'] as String
            : 'Sign-in failed. Check the server and try again.',
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'PeerPass',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MUST operations',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in with a provisioned administrator account.',
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_busy ? 'Signing in...' : 'Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({required this.session, super.key});

  final AdminSession session;

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const UsersPage(),
      const CompetenciesPage(),
      const TutorStandingsPage(),
      const AuditPage(),
    ];
    const destinations = [
      NavigationRailDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: Text('Users'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.verified_outlined),
        label: Text('Competencies'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.verified_user_outlined),
        label: Text('Tutor standing'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.history),
        label: Text('Audit log'),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('PeerPass Admin'),
        actions: [
          Text(widget.session.email),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () {
              ref.read(apiProvider).signOut();
              ref.read(sessionProvider.notifier).signedOut();
            },
            child: const Text('Sign out'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return pages[_selected];
          }
          return Row(
            children: [
              NavigationRail(
                selectedIndex: _selected,
                onDestinationSelected: (value) =>
                    setState(() => _selected = value),
                labelType: NavigationRailLabelType.all,
                destinations: destinations,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: pages[_selected]),
            ],
          );
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 700
            ? NavigationBar(
                selectedIndex: _selected,
                onDestinationSelected: (value) =>
                    setState(() => _selected = value),
                destinations: [
                  for (final destination in destinations)
                    NavigationDestination(
                      icon: destination.icon,
                      selectedIcon: destination.selectedIcon,
                      label: (destination.label as Text).data!,
                    ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminDataTable<AdminUser>(
      title: 'Pilot users',
      subtitle: 'Operational visibility for invited students and tutors.',
      loader: () => ref.read(apiProvider).users(),
      columns: const ['Name', 'Email', 'Roles', 'Status', 'Created'],
      row: (user) => [
        user.name ?? 'Unnamed account',
        user.email,
        user.roles.join(', '),
        user.isActive ? 'Active' : 'Inactive',
        _date(user.createdAt),
      ],
    );
  }
}

class AuditPage extends ConsumerWidget {
  const AuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminDataTable<AuditEvent>(
      title: 'Audit log',
      subtitle: 'Append-only record of privileged administrative actions.',
      loader: () => ref.read(apiProvider).auditEvents(),
      columns: const ['Action', 'Target', 'Created'],
      row: (event) => [event.action, event.targetType, _date(event.createdAt)],
    );
  }
}

class CompetenciesPage extends ConsumerWidget {
  const CompetenciesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminDataTable<AdminCompetency>(
      title: 'Competency review',
      subtitle: 'Review tutor evidence before granting matching eligibility.',
      loader: () => ref.read(apiProvider).competencies(),
      columns: const ['Tutor', 'Unit', 'Grade', 'Status', 'Evidence'],
      row: (competency) => [
        competency.name ?? competency.email,
        competency.unit,
        competency.grade,
        competency.status,
        competency.evidence ?? 'Not supplied',
      ],
      actions: (competency, refresh) => competency.status == 'pending'
          ? [
              TextButton(
                onPressed: () async {
                  try {
                    await ref
                        .read(apiProvider)
                        .reviewCompetency(competency, 'verified');
                    refresh();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Competency verified.')),
                      );
                    }
                  } on DioException {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not verify competency.'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Verify'),
              ),
              TextButton(
                onPressed: () async {
                  final reason = await showDialog<String>(
                    context: context,
                    builder: (context) => const _RejectionReasonDialog(),
                  );
                  if (reason == null || reason.trim().isEmpty) return;
                  try {
                    await ref
                        .read(apiProvider)
                        .reviewCompetency(
                          competency,
                          'rejected',
                          reason: reason.trim(),
                        );
                    refresh();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Competency rejected.')),
                      );
                    }
                  } on DioException {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not reject competency.'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Reject'),
              ),
            ]
          : const [],
    );
  }
}

class TutorStandingsPage extends ConsumerWidget {
  const TutorStandingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminDataTable<AdminTutorStanding>(
      title: 'Tutor standing',
      subtitle: 'Review current standing and rating aggregates.',
      loader: () => ref.read(apiProvider).tutorStandings(),
      columns: const ['Tutor', 'Standing', 'Sessions', 'Average rating'],
      row: (standing) => [
        standing.name ?? standing.email,
        standing.standing,
        '${standing.sessions}',
        standing.rating ?? 'Unrated',
      ],
    );
  }
}

class _RejectionReasonDialog extends StatefulWidget {
  const _RejectionReasonDialog();

  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject competency'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Reason',
          hintText: 'Explain what needs to be corrected.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Reject'),
        ),
      ],
    );
  }
}

class AdminDataTable<T> extends StatefulWidget {
  const AdminDataTable({
    required this.title,
    required this.subtitle,
    required this.loader,
    required this.columns,
    required this.row,
    this.actions,
    super.key,
  });

  final String title;
  final String subtitle;
  final Future<AdminPage<T>> Function() loader;
  final List<String> columns;
  final List<String> Function(T item) row;
  final List<Widget> Function(T item, VoidCallback refresh)? actions;

  @override
  State<AdminDataTable<T>> createState() => _AdminDataTableState<T>();
}

class _AdminDataTableState<T> extends State<AdminDataTable<T>> {
  late Future<AdminPage<T>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: _ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.subtitle, style: const TextStyle(color: _muted)),
          const SizedBox(height: 24),
          Expanded(
            child: FutureBuilder<AdminPage<T>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load this view.'),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () =>
                              setState(() => _future = widget.loader()),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final page = snapshot.requireData;
                if (page.items.isEmpty) {
                  return const Center(child: Text('No records yet.'));
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        for (final column in [
                          ...widget.columns,
                          if (widget.actions != null) 'Actions',
                        ])
                          DataColumn(label: Text(column)),
                      ],
                      rows: [
                        for (final item in page.items)
                          DataRow(
                            cells: [
                              for (final value in widget.row(item))
                                DataCell(Text(value)),
                              if (widget.actions != null)
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: widget.actions!(
                                      item,
                                      () => setState(
                                        () => _future = widget.loader(),
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
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
