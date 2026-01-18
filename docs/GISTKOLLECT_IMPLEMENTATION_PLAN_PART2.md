# GiSTKollect Implementation Plan - Part 2

## Phases 7-15: Detailed Instructions

This document continues from GISTKOLLECT_IMPLEMENTATION_PLAN.md with detailed instructions for Phases 7-15.

---

## Phase 7: Web App - Projects Management

**Estimated time: 3-4 hours**

### Step 7.1: Create Project Model

**lib/models/project.dart:**

```dart
class Project {
  final String id;
  final String name;
  final String? description;
  final String slug;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;

  Project({
    required this.id,
    required this.name,
    this.description,
    required this.slug,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      slug: json['slug'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'slug': slug,
      'created_by': createdBy,
      'is_active': isActive,
    };
  }
}
```

### Step 7.2: Create Project Member Model

**lib/models/project_member.dart:**

```dart
enum ProjectRole {
  viewer,
  dataAnalyst,
  editor,
  admin,
  owner;

  String get displayName {
    switch (this) {
      case ProjectRole.viewer:
        return 'Viewer';
      case ProjectRole.dataAnalyst:
        return 'Data Analyst';
      case ProjectRole.editor:
        return 'Editor';
      case ProjectRole.admin:
        return 'Admin';
      case ProjectRole.owner:
        return 'Owner';
    }
  }

  String get databaseValue {
    switch (this) {
      case ProjectRole.viewer:
        return 'viewer';
      case ProjectRole.dataAnalyst:
        return 'data_analyst';
      case ProjectRole.editor:
        return 'editor';
      case ProjectRole.admin:
        return 'admin';
      case ProjectRole.owner:
        return 'owner';
    }
  }

  static ProjectRole fromString(String value) {
    switch (value) {
      case 'viewer':
        return ProjectRole.viewer;
      case 'data_analyst':
        return ProjectRole.dataAnalyst;
      case 'editor':
        return ProjectRole.editor;
      case 'admin':
        return ProjectRole.admin;
      case 'owner':
        return ProjectRole.owner;
      default:
        return ProjectRole.viewer;
    }
  }

  bool get canManageSurveys =>
      this == ProjectRole.editor ||
      this == ProjectRole.admin ||
      this == ProjectRole.owner;

  bool get canExportData => this != ProjectRole.viewer;

  bool get canManageTeam =>
      this == ProjectRole.admin || this == ProjectRole.owner;

  bool get canDeleteProject => this == ProjectRole.owner;
}

class ProjectMember {
  final String id;
  final String projectId;
  final String userId;
  final ProjectRole role;
  final String? invitedBy;
  final DateTime? invitedAt;
  final DateTime? acceptedAt;
  final Map<String, dynamic>? profile; // Joined profile data

  ProjectMember({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.role,
    this.invitedBy,
    this.invitedAt,
    this.acceptedAt,
    this.profile,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      id: json['id'],
      projectId: json['project_id'],
      userId: json['user_id'],
      role: ProjectRole.fromString(json['role']),
      invitedBy: json['invited_by'],
      invitedAt: json['invited_at'] != null
          ? DateTime.parse(json['invited_at'])
          : null,
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'])
          : null,
      profile: json['profiles'],
    );
  }

  String get displayName =>
      profile?['full_name'] ?? profile?['email'] ?? 'Unknown';
  String get email => profile?['email'] ?? '';
}
```

### Step 7.3: Create Project Service

**lib/services/project_service.dart:**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project.dart';
import '../models/project_member.dart';

class ProjectService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser!.id;

  /// Get all projects the current user is a member of
  Future<List<Project>> getProjects() async {
    final response = await _supabase
        .from('projects')
        .select()
        .eq('is_active', true)
        .order('name');

    return (response as List).map((p) => Project.fromJson(p)).toList();
  }

  /// Get a single project by ID
  Future<Project?> getProject(String projectId) async {
    final response = await _supabase
        .from('projects')
        .select()
        .eq('id', projectId)
        .single();

    return Project.fromJson(response);
  }

  /// Get user's role in a project
  Future<ProjectRole?> getUserRole(String projectId) async {
    final response = await _supabase
        .from('project_members')
        .select('role')
        .eq('project_id', projectId)
        .eq('user_id', _userId)
        .maybeSingle();

    if (response == null) return null;
    return ProjectRole.fromString(response['role']);
  }

  /// Create a new project
  Future<Project> createProject({
    required String name,
    String? description,
    required String slug,
  }) async {
    // Create project
    final projectResponse = await _supabase
        .from('projects')
        .insert({
          'name': name,
          'description': description,
          'slug': slug.toLowerCase().trim(),
          'created_by': _userId,
        })
        .select()
        .single();

    final project = Project.fromJson(projectResponse);

    // Add creator as owner
    await _supabase.from('project_members').insert({
      'project_id': project.id,
      'user_id': _userId,
      'role': 'owner',
      'accepted_at': DateTime.now().toIso8601String(),
    });

    return project;
  }

  /// Update project details
  Future<Project> updateProject({
    required String projectId,
    String? name,
    String? description,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;

    final response = await _supabase
        .from('projects')
        .update(updates)
        .eq('id', projectId)
        .select()
        .single();

    return Project.fromJson(response);
  }

  /// Delete project (soft delete)
  Future<void> deleteProject(String projectId) async {
    await _supabase
        .from('projects')
        .update({'is_active': false})
        .eq('id', projectId);
  }

  /// Check if slug is available
  Future<bool> isSlugAvailable(String slug) async {
    final response = await _supabase
        .from('projects')
        .select('id')
        .eq('slug', slug.toLowerCase().trim())
        .maybeSingle();

    return response == null;
  }

  /// Generate slug from name
  String generateSlug(String name) {
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
  }
}
```

### Step 7.4: Create Project Provider

**lib/providers/project_provider.dart:**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project.dart';
import '../models/project_member.dart';
import '../services/project_service.dart';

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService();
});

final projectsProvider = FutureProvider<List<Project>>((ref) async {
  final service = ref.watch(projectServiceProvider);
  return await service.getProjects();
});

final projectProvider =
    FutureProvider.family<Project?, String>((ref, projectId) async {
  final service = ref.watch(projectServiceProvider);
  return await service.getProject(projectId);
});

final userRoleProvider =
    FutureProvider.family<ProjectRole?, String>((ref, projectId) async {
  final service = ref.watch(projectServiceProvider);
  return await service.getUserRole(projectId);
});
```

### Step 7.5: Create Projects List Screen

**lib/screens/projects/projects_list_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/project_provider.dart';
import '../../providers/auth_provider.dart';

class ProjectsListScreen extends ConsumerWidget {
  const ProjectsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider);
    final authService = ref.read(authServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Projects'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: projectsAsync.when(
        data: (projects) {
          if (projects.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No projects yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first project to get started',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/projects/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Create Project'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      project.name[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    project.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (project.description != null &&
                          project.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            project.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${project.slug}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/projects/${project.id}'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text('Error loading projects: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(projectsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/projects/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
      ),
    );
  }
}
```

### Step 7.6: Create Project Screen

**lib/screens/projects/create_project_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/project_provider.dart';

class CreateProjectScreen extends ConsumerStatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  ConsumerState<CreateProjectScreen> createState() =>
      _CreateProjectScreenState();
}

class _CreateProjectScreenState extends ConsumerState<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _slugController = TextEditingController();

  bool _isLoading = false;
  bool _isCheckingSlug = false;
  bool? _slugAvailable;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _slugController.dispose();
    super.dispose();
  }

  void _onNameChanged(String name) {
    final service = ref.read(projectServiceProvider);
    final slug = service.generateSlug(name);
    _slugController.text = slug;
    _checkSlugAvailability(slug);
  }

  Future<void> _checkSlugAvailability(String slug) async {
    if (slug.isEmpty) {
      setState(() => _slugAvailable = null);
      return;
    }

    setState(() => _isCheckingSlug = true);

    final service = ref.read(projectServiceProvider);
    final available = await service.isSlugAvailable(slug);

    if (mounted) {
      setState(() {
        _slugAvailable = available;
        _isCheckingSlug = false;
      });
    }
  }

  Future<void> _createProject() async {
    if (!_formKey.currentState!.validate()) return;
    if (_slugAvailable != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(projectServiceProvider);
      final project = await service.createProject(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        slug: _slugController.text.trim(),
      );

      // Refresh projects list
      ref.invalidate(projectsProvider);

      if (mounted) {
        context.go('/projects/${project.id}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create project: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Project'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/projects'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'New Project',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a new project to start managing surveys and collecting data.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 32),

                  // Project name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Project Name *',
                      hintText: 'e.g., R21 Vaccine Study',
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: _onNameChanged,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a project name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Project code (slug)
                  TextFormField(
                    controller: _slugController,
                    decoration: InputDecoration(
                      labelText: 'Project Code *',
                      hintText: 'e.g., r21-vaccine',
                      helperText:
                          'Used for app login. Only lowercase letters, numbers, and hyphens.',
                      suffixIcon: _isCheckingSlug
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : _slugAvailable == true
                              ? const Icon(Icons.check_circle,
                                  color: Colors.green)
                              : _slugAvailable == false
                                  ? const Icon(Icons.error, color: Colors.red)
                                  : null,
                    ),
                    onChanged: (value) => _checkSlugAvailability(value),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a project code';
                      }
                      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                        return 'Only lowercase letters, numbers, and hyphens allowed';
                      }
                      if (_slugAvailable == false) {
                        return 'This project code is already taken';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      hintText: 'Brief description of the project',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                  // Error message
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),

                  // Create button
                  ElevatedButton(
                    onPressed: _isLoading || _slugAvailable != true
                        ? null
                        : _createProject,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create Project'),
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
```

### Step 7.7: Update Home Screen

**lib/screens/home/home_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Redirect to projects list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.go('/projects');
    });

    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
```

### Step 7.8: Checklist

- [ ] Project model created
- [ ] ProjectMember model created
- [ ] Project service created
- [ ] Project provider created
- [ ] Projects list screen created
- [ ] Create project screen created
- [ ] Project creation working
- [ ] Slug validation working

---

## Phase 8: Web App - Survey Management

**Estimated time: 4-6 hours**

### Step 8.1: Create Survey Package Model

**lib/models/survey_package.dart:**

```dart
enum SurveyStatus {
  draft,
  processing,
  ready,
  archived,
  error;

  String get displayName {
    switch (this) {
      case SurveyStatus.draft:
        return 'Draft';
      case SurveyStatus.processing:
        return 'Processing';
      case SurveyStatus.ready:
        return 'Ready';
      case SurveyStatus.archived:
        return 'Archived';
      case SurveyStatus.error:
        return 'Error';
    }
  }

  static SurveyStatus fromString(String value) {
    switch (value) {
      case 'draft':
        return SurveyStatus.draft;
      case 'processing':
        return SurveyStatus.processing;
      case 'ready':
        return SurveyStatus.ready;
      case 'archived':
        return SurveyStatus.archived;
      case 'error':
        return SurveyStatus.error;
      default:
        return SurveyStatus.draft;
    }
  }
}

class SurveyPackage {
  final String id;
  final String projectId;
  final String name;
  final String? version;
  final String? description;
  final String? excelFilePath;
  final String? zipFilePath;
  final Map<String, dynamic>? manifest;
  final SurveyStatus status;
  final String? errorMessage;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;

  SurveyPackage({
    required this.id,
    required this.projectId,
    required this.name,
    this.version,
    this.description,
    this.excelFilePath,
    this.zipFilePath,
    this.manifest,
    required this.status,
    this.errorMessage,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
  });

  factory SurveyPackage.fromJson(Map<String, dynamic> json) {
    return SurveyPackage(
      id: json['id'],
      projectId: json['project_id'],
      name: json['name'],
      version: json['version'],
      description: json['description'],
      excelFilePath: json['excel_file_path'],
      zipFilePath: json['zip_file_path'],
      manifest: json['manifest'],
      status: SurveyStatus.fromString(json['status'] ?? 'draft'),
      errorMessage: json['error_message'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'])
          : null,
    );
  }
}
```

### Step 8.2: Create CRF Model

**lib/models/crf.dart:**

```dart
class Crf {
  final String id;
  final String surveyPackageId;
  final String projectId;
  final String tableName;
  final String displayName;
  final int displayOrder;
  final bool isBase;
  final String? primaryKey;
  final String? linkingField;
  final String? parentTable;
  final List<CrfField> fields;
  final Map<String, dynamic>? idConfig;
  final String? displayFields;

  Crf({
    required this.id,
    required this.surveyPackageId,
    required this.projectId,
    required this.tableName,
    required this.displayName,
    this.displayOrder = 0,
    this.isBase = false,
    this.primaryKey,
    this.linkingField,
    this.parentTable,
    this.fields = const [],
    this.idConfig,
    this.displayFields,
  });

  factory Crf.fromJson(Map<String, dynamic> json) {
    final fieldsJson = json['fields'] as List<dynamic>? ?? [];
    return Crf(
      id: json['id'],
      surveyPackageId: json['survey_package_id'],
      projectId: json['project_id'],
      tableName: json['table_name'],
      displayName: json['display_name'],
      displayOrder: json['display_order'] ?? 0,
      isBase: json['is_base'] ?? false,
      primaryKey: json['primary_key'],
      linkingField: json['linking_field'],
      parentTable: json['parent_table'],
      fields: fieldsJson.map((f) => CrfField.fromJson(f)).toList(),
      idConfig: json['id_config'],
      displayFields: json['display_fields'],
    );
  }
}

class CrfField {
  final String fieldName;
  final String fieldType;
  final String? questionType;
  final String? text;
  final bool isRequired;

  CrfField({
    required this.fieldName,
    required this.fieldType,
    this.questionType,
    this.text,
    this.isRequired = false,
  });

  factory CrfField.fromJson(Map<String, dynamic> json) {
    return CrfField(
      fieldName: json['fieldname'] ?? json['fieldName'],
      fieldType: json['fieldtype'] ?? json['fieldType'] ?? 'text',
      questionType: json['question_type'] ?? json['questionType'],
      text: json['text'],
      isRequired: json['required'] ?? false,
    );
  }
}
```

### Step 8.3: Create Survey Service

**lib/services/survey_service.dart:**

```dart
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/survey_package.dart';
import '../models/crf.dart';

class SurveyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser!.id;

  /// Get all surveys for a project
  Future<List<SurveyPackage>> getSurveys(String projectId) async {
    final response = await _supabase
        .from('survey_packages')
        .select()
        .eq('project_id', projectId)
        .order('created_at', ascending: false);

    return (response as List).map((s) => SurveyPackage.fromJson(s)).toList();
  }

  /// Get a single survey by ID
  Future<SurveyPackage?> getSurvey(String surveyId) async {
    final response = await _supabase
        .from('survey_packages')
        .select()
        .eq('id', surveyId)
        .single();

    return SurveyPackage.fromJson(response);
  }

  /// Get CRFs for a survey
  Future<List<Crf>> getCrfs(String surveyPackageId) async {
    final response = await _supabase
        .from('crfs')
        .select()
        .eq('survey_package_id', surveyPackageId)
        .order('display_order');

    return (response as List).map((c) => Crf.fromJson(c)).toList();
  }

  /// Create a new survey package (draft)
  Future<SurveyPackage> createSurvey({
    required String projectId,
    required String name,
    String? version,
    String? description,
  }) async {
    final response = await _supabase
        .from('survey_packages')
        .insert({
          'project_id': projectId,
          'name': name,
          'version': version,
          'description': description,
          'status': 'draft',
          'created_by': _userId,
        })
        .select()
        .single();

    return SurveyPackage.fromJson(response);
  }

  /// Upload Excel file to storage
  Future<String> uploadExcelFile({
    required String projectId,
    required String surveyId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    final path = '$projectId/$surveyId/source/$fileName';

    await _supabase.storage.from('uploads').uploadBinary(
          path,
          fileBytes,
          fileOptions: const FileOptions(
            contentType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        );

    return path;
  }

  /// Upload CSV file to storage
  Future<String> uploadCsvFile({
    required String projectId,
    required String surveyId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    final path = '$projectId/$surveyId/csv/$fileName';

    await _supabase.storage.from('uploads').uploadBinary(
          path,
          fileBytes,
          fileOptions: const FileOptions(contentType: 'text/csv'),
        );

    return path;
  }

  /// Upload generated ZIP file
  Future<String> uploadZipFile({
    required String projectId,
    required String surveyId,
    required String fileName,
    required Uint8List fileBytes,
  }) async {
    final path = '$projectId/$surveyId/$fileName';

    await _supabase.storage.from('surveys').uploadBinary(
          path,
          fileBytes,
          fileOptions: const FileOptions(contentType: 'application/zip'),
        );

    return path;
  }

  /// Update survey with manifest and ZIP path
  Future<SurveyPackage> publishSurvey({
    required String surveyId,
    required String zipFilePath,
    required Map<String, dynamic> manifest,
  }) async {
    final response = await _supabase
        .from('survey_packages')
        .update({
          'zip_file_path': zipFilePath,
          'manifest': manifest,
          'status': 'ready',
          'published_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', surveyId)
        .select()
        .single();

    return SurveyPackage.fromJson(response);
  }

  /// Save CRF definitions
  Future<void> saveCrfs({
    required String surveyPackageId,
    required String projectId,
    required List<Map<String, dynamic>> crfs,
  }) async {
    // Delete existing CRFs for this survey
    await _supabase
        .from('crfs')
        .delete()
        .eq('survey_package_id', surveyPackageId);

    // Insert new CRFs
    for (final crf in crfs) {
      await _supabase.from('crfs').insert({
        'survey_package_id': surveyPackageId,
        'project_id': projectId,
        'table_name': crf['tablename'],
        'display_name': crf['displayname'],
        'display_order': crf['display_order'] ?? 0,
        'is_base': crf['isbase'] == 1,
        'primary_key': crf['primarykey'],
        'linking_field': crf['linkingfield'],
        'parent_table': crf['parent_table'],
        'fields': crf['fields'],
        'id_config': crf['idconfig'],
        'display_fields': crf['display_fields'],
      });
    }
  }

  /// Get download URL for a survey ZIP
  Future<String?> getDownloadUrl(String zipFilePath) async {
    final response = await _supabase.storage
        .from('surveys')
        .createSignedUrl(zipFilePath, 3600); // 1 hour expiry

    return response;
  }

  /// Delete a survey
  Future<void> deleteSurvey(String surveyId) async {
    await _supabase.from('survey_packages').delete().eq('id', surveyId);
  }

  /// Update survey status to error
  Future<void> markSurveyError({
    required String surveyId,
    required String errorMessage,
  }) async {
    await _supabase.from('survey_packages').update({
      'status': 'error',
      'error_message': errorMessage,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', surveyId);
  }
}
```

### Step 8.4: Create Survey Provider

**lib/providers/survey_provider.dart:**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/survey_package.dart';
import '../models/crf.dart';
import '../services/survey_service.dart';

final surveyServiceProvider = Provider<SurveyService>((ref) {
  return SurveyService();
});

final surveysProvider =
    FutureProvider.family<List<SurveyPackage>, String>((ref, projectId) async {
  final service = ref.watch(surveyServiceProvider);
  return await service.getSurveys(projectId);
});

final surveyProvider =
    FutureProvider.family<SurveyPackage?, String>((ref, surveyId) async {
  final service = ref.watch(surveyServiceProvider);
  return await service.getSurvey(surveyId);
});

final crfsProvider =
    FutureProvider.family<List<Crf>, String>((ref, surveyPackageId) async {
  final service = ref.watch(surveyServiceProvider);
  return await service.getCrfs(surveyPackageId);
});
```

### Step 8.5: Create Project Dashboard Screen

**lib/screens/dashboard/project_dashboard_screen.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/project_provider.dart';
import '../../models/project_member.dart';
import 'surveys_tab.dart';
import 'data_tab.dart';
import 'reports_tab.dart';
import 'team_tab.dart';

class ProjectDashboardScreen extends ConsumerStatefulWidget {
  final String projectId;

  const ProjectDashboardScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProjectDashboardScreen> createState() =>
      _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState
    extends ConsumerState<ProjectDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectProvider(widget.projectId));
    final roleAsync = ref.watch(userRoleProvider(widget.projectId));

    return projectAsync.when(
      data: (project) {
        if (project == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project Not Found')),
            body: const Center(child: Text('Project not found')),
          );
        }

        return roleAsync.when(
          data: (role) {
            final tabs = _buildTabs(role);
            final tabViews = _buildTabViews(role);

            return Scaffold(
              appBar: AppBar(
                title: Text(project.name),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.go('/projects'),
                ),
                bottom: TabBar(
                  controller: TabController(
                    length: tabs.length,
                    vsync: Scaffold.of(context),
                    initialIndex: _selectedIndex,
                  ),
                  tabs: tabs,
                  onTap: (index) => setState(() => _selectedIndex = index),
                ),
              ),
              body: IndexedStack(
                index: _selectedIndex,
                children: tabViews,
              ),
            );
          },
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  List<Tab> _buildTabs(ProjectRole? role) {
    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
    ];

    if (role?.canManageSurveys ?? false) {
      tabs.add(const Tab(icon: Icon(Icons.assignment), text: 'Surveys'));
    }

    tabs.add(const Tab(icon: Icon(Icons.folder), text: 'Data'));

    if (role?.canExportData ?? false) {
      tabs.add(const Tab(icon: Icon(Icons.bar_chart), text: 'Reports'));
    }

    if (role?.canManageTeam ?? false) {
      tabs.add(const Tab(icon: Icon(Icons.people), text: 'Team'));
    }

    return tabs;
  }

  List<Widget> _buildTabViews(ProjectRole? role) {
    final views = <Widget>[
      _buildDashboardTab(),
    ];

    if (role?.canManageSurveys ?? false) {
      views.add(SurveysTab(projectId: widget.projectId));
    }

    views.add(DataTab(projectId: widget.projectId));

    if (role?.canExportData ?? false) {
      views.add(ReportsTab(projectId: widget.projectId));
    }

    if (role?.canManageTeam ?? false) {
      views.add(TeamTab(projectId: widget.projectId));
    }

    return views;
  }

  Widget _buildDashboardTab() {
    return const Center(
      child: Text('Dashboard - Overview coming soon'),
    );
  }
}
```

### Step 8.6: Create Surveys Tab

**lib/screens/dashboard/surveys_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../providers/survey_provider.dart';
import '../../models/survey_package.dart';

class SurveysTab extends ConsumerWidget {
  final String projectId;

  const SurveysTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surveysAsync = ref.watch(surveysProvider(projectId));

    return surveysAsync.when(
      data: (surveys) {
        if (surveys.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_outlined,
                    size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No surveys yet',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                const Text('Upload an Excel file to create a survey'),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _showUploadDialog(context, ref),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload Survey'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${surveys.length} Survey${surveys.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showUploadDialog(context, ref),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload Survey'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: surveys.length,
                itemBuilder: (context, index) {
                  final survey = surveys[index];
                  return _buildSurveyCard(context, ref, survey);
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildSurveyCard(
      BuildContext context, WidgetRef ref, SurveyPackage survey) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: _buildStatusIcon(survey.status),
        title: Row(
          children: [
            Expanded(
              child: Text(
                survey.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (survey.version != null)
              Chip(
                label: Text('v${survey.version}'),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Created: ${dateFormat.format(survey.createdAt)}'),
            if (survey.publishedAt != null)
              Text('Published: ${dateFormat.format(survey.publishedAt!)}'),
            if (survey.errorMessage != null)
              Text(
                'Error: ${survey.errorMessage}',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            if (survey.status == SurveyStatus.ready)
              const PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 8),
                    Text('Download ZIP'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) async {
            if (value == 'download') {
              await _downloadSurvey(context, ref, survey);
            } else if (value == 'delete') {
              await _deleteSurvey(context, ref, survey);
            }
          },
        ),
      ),
    );
  }

  Widget _buildStatusIcon(SurveyStatus status) {
    IconData icon;
    Color color;

    switch (status) {
      case SurveyStatus.draft:
        icon = Icons.edit;
        color = Colors.grey;
        break;
      case SurveyStatus.processing:
        icon = Icons.hourglass_top;
        color = Colors.orange;
        break;
      case SurveyStatus.ready:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case SurveyStatus.archived:
        icon = Icons.archive;
        color = Colors.grey;
        break;
      case SurveyStatus.error:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(icon, color: color),
    );
  }

  void _showUploadDialog(BuildContext context, WidgetRef ref) {
    // TODO: Implement upload dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Upload dialog coming soon')),
    );
  }

  Future<void> _downloadSurvey(
      BuildContext context, WidgetRef ref, SurveyPackage survey) async {
    // TODO: Implement download
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download coming soon')),
    );
  }

  Future<void> _deleteSurvey(
      BuildContext context, WidgetRef ref, SurveyPackage survey) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Survey'),
        content: Text('Are you sure you want to delete "${survey.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final service = ref.read(surveyServiceProvider);
      await service.deleteSurvey(survey.id);
      ref.invalidate(surveysProvider(projectId));
    }
  }
}
```

### Step 8.7: Create Placeholder Tabs

**lib/screens/dashboard/data_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DataTab extends ConsumerWidget {
  final String projectId;

  const DataTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(
      child: Text('Data viewing - Coming in Phase 10'),
    );
  }
}
```

**lib/screens/dashboard/reports_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReportsTab extends ConsumerWidget {
  final String projectId;

  const ReportsTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(
      child: Text('Reports - Coming in Phase 10'),
    );
  }
}
```

**lib/screens/dashboard/team_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TeamTab extends ConsumerWidget {
  final String projectId;

  const TeamTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(
      child: Text('Team management - Coming in Phase 9'),
    );
  }
}
```

### Step 8.8: Checklist

- [ ] SurveyPackage model created
- [ ] Crf model created
- [ ] Survey service created
- [ ] Survey provider created
- [ ] Project dashboard screen created
- [ ] Surveys tab created
- [ ] Placeholder tabs created
- [ ] Survey listing working

---

## Phase 9: Web App - Team & Credentials

**Estimated time: 3-4 hours**

### Step 9.1: Create Team Service

**lib/services/team_service.dart:**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/project_member.dart';

class TeamService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser!.id;

  /// Get all members of a project
  Future<List<ProjectMember>> getMembers(String projectId) async {
    final response = await _supabase
        .from('project_members')
        .select('*, profiles(*)')
        .eq('project_id', projectId)
        .order('role');

    return (response as List).map((m) => ProjectMember.fromJson(m)).toList();
  }

  /// Invite a user to a project
  Future<void> inviteMember({
    required String projectId,
    required String email,
    required ProjectRole role,
  }) async {
    // First, find user by email
    final userResponse = await _supabase
        .from('profiles')
        .select('id')
        .eq('email', email)
        .maybeSingle();

    if (userResponse == null) {
      throw Exception('User not found. They must create an account first.');
    }

    final userId = userResponse['id'];

    // Check if already a member
    final existingMember = await _supabase
        .from('project_members')
        .select('id')
        .eq('project_id', projectId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existingMember != null) {
      throw Exception('User is already a member of this project.');
    }

    // Add membership
    await _supabase.from('project_members').insert({
      'project_id': projectId,
      'user_id': userId,
      'role': role.databaseValue,
      'invited_by': _userId,
      'invited_at': DateTime.now().toIso8601String(),
      'accepted_at': DateTime.now().toIso8601String(), // Auto-accept for now
    });
  }

  /// Update a member's role
  Future<void> updateMemberRole({
    required String memberId,
    required ProjectRole newRole,
  }) async {
    await _supabase
        .from('project_members')
        .update({'role': newRole.databaseValue})
        .eq('id', memberId);
  }

  /// Remove a member from project
  Future<void> removeMember(String memberId) async {
    await _supabase.from('project_members').delete().eq('id', memberId);
  }
}
```

### Step 9.2: Create Credential Service

**lib/services/credential_service.dart:**

```dart
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppCredential {
  final String id;
  final String projectId;
  final String username;
  final String? description;
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  AppCredential({
    required this.id,
    required this.projectId,
    required this.username,
    this.description,
    required this.isActive,
    this.createdBy,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory AppCredential.fromJson(Map<String, dynamic> json) {
    return AppCredential(
      id: json['id'],
      projectId: json['project_id'],
      username: json['username'],
      description: json['description'],
      isActive: json['is_active'] ?? true,
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'])
          : null,
    );
  }
}

class CredentialService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String get _userId => _supabase.auth.currentUser!.id;

  /// Get all credentials for a project
  Future<List<AppCredential>> getCredentials(String projectId) async {
    final response = await _supabase
        .from('app_credentials')
        .select()
        .eq('project_id', projectId)
        .order('username');

    return (response as List).map((c) => AppCredential.fromJson(c)).toList();
  }

  /// Create new app credentials
  /// Returns the plain text password (only available at creation time)
  Future<({AppCredential credential, String password})> createCredential({
    required String projectId,
    required String username,
    String? description,
    String? password,
  }) async {
    // Generate password if not provided
    final plainPassword = password ?? _generatePassword(12);

    // Hash password using bcrypt-like approach
    // Note: In production, use the Edge Function for proper bcrypt hashing
    final passwordHash = _hashPassword(plainPassword);

    final response = await _supabase
        .from('app_credentials')
        .insert({
          'project_id': projectId,
          'username': username,
          'password_hash': passwordHash,
          'description': description,
          'created_by': _userId,
        })
        .select()
        .single();

    return (
      credential: AppCredential.fromJson(response),
      password: plainPassword,
    );
  }

  /// Update credential (description only)
  Future<void> updateCredential({
    required String credentialId,
    String? description,
  }) async {
    await _supabase.from('app_credentials').update({
      'description': description,
    }).eq('id', credentialId);
  }

  /// Deactivate credential
  Future<void> deactivateCredential(String credentialId) async {
    await _supabase
        .from('app_credentials')
        .update({'is_active': false})
        .eq('id', credentialId);
  }

  /// Activate credential
  Future<void> activateCredential(String credentialId) async {
    await _supabase
        .from('app_credentials')
        .update({'is_active': true})
        .eq('id', credentialId);
  }

  /// Delete credential
  Future<void> deleteCredential(String credentialId) async {
    await _supabase.from('app_credentials').delete().eq('id', credentialId);
  }

  /// Regenerate password for a credential
  Future<String> regeneratePassword(String credentialId) async {
    final plainPassword = _generatePassword(12);
    final passwordHash = _hashPassword(plainPassword);

    await _supabase
        .from('app_credentials')
        .update({'password_hash': passwordHash})
        .eq('id', credentialId);

    return plainPassword;
  }

  /// Generate a random password
  String _generatePassword(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Hash password (simple implementation - Edge Function uses bcrypt)
  String _hashPassword(String password) {
    // This is a placeholder - the actual hashing should be done server-side
    // For now, we'll use SHA-256 with a prefix to indicate it needs proper hashing
    final bytes = utf8.encode(password);
    final hash = sha256.convert(bytes);
    return 'sha256:$hash';
  }
}
```

### Step 9.3: Create Team Provider

**lib/providers/team_provider.dart:**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/project_member.dart';
import '../services/team_service.dart';
import '../services/credential_service.dart';

final teamServiceProvider = Provider<TeamService>((ref) => TeamService());

final credentialServiceProvider =
    Provider<CredentialService>((ref) => CredentialService());

final membersProvider =
    FutureProvider.family<List<ProjectMember>, String>((ref, projectId) async {
  final service = ref.watch(teamServiceProvider);
  return await service.getMembers(projectId);
});

final credentialsProvider =
    FutureProvider.family<List<AppCredential>, String>((ref, projectId) async {
  final service = ref.watch(credentialServiceProvider);
  return await service.getCredentials(projectId);
});
```

### Step 9.4: Update Team Tab

**lib/screens/dashboard/team_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/team_provider.dart';
import '../../models/project_member.dart';
import '../../services/credential_service.dart';

class TeamTab extends ConsumerWidget {
  final String projectId;

  const TeamTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Team Members'),
              Tab(text: 'App Credentials'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _MembersTab(projectId: projectId),
                _CredentialsTab(projectId: projectId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  final String projectId;

  const _MembersTab({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(membersProvider(projectId));

    return membersAsync.when(
      data: (members) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${members.length} Member${members.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showInviteDialog(context, ref),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Invite'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final member = members[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(member.displayName[0].toUpperCase()),
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(member.email),
                    trailing: Chip(label: Text(member.role.displayName)),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final emailController = TextEditingController();
    ProjectRole selectedRole = ProjectRole.viewer;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Invite Team Member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'user@example.com',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ProjectRole>(
                value: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: ProjectRole.values
                    .where((r) => r != ProjectRole.owner)
                    .map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role.displayName),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedRole = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final service = ref.read(teamServiceProvider);
                  await service.inviteMember(
                    projectId: projectId,
                    email: emailController.text.trim(),
                    role: selectedRole,
                  );
                  ref.invalidate(membersProvider(projectId));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Member invited')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialsTab extends ConsumerWidget {
  final String projectId;

  const _CredentialsTab({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentialsAsync = ref.watch(credentialsProvider(projectId));
    final dateFormat = DateFormat('MMM d, yyyy');

    return credentialsAsync.when(
      data: (credentials) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${credentials.length} Credential${credentials.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: credentials.isEmpty
                  ? const Center(child: Text('No app credentials yet'))
                  : ListView.builder(
                      itemCount: credentials.length,
                      itemBuilder: (context, index) {
                        final cred = credentials[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              cred.isActive ? Icons.key : Icons.key_off,
                              color:
                                  cred.isActive ? Colors.green : Colors.grey,
                            ),
                            title: Text(cred.username),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (cred.description != null)
                                  Text(cred.description!),
                                Text(
                                  cred.lastUsedAt != null
                                      ? 'Last used: ${dateFormat.format(cred.lastUsedAt!)}'
                                      : 'Never used',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: cred.isActive ? 'deactivate' : 'activate',
                                  child: Text(cred.isActive
                                      ? 'Deactivate'
                                      : 'Activate'),
                                ),
                                const PopupMenuItem(
                                  value: 'regenerate',
                                  child: Text('Regenerate Password'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                              onSelected: (value) =>
                                  _handleCredentialAction(context, ref, cred, value),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final usernameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create App Credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'e.g., fieldteam_uganda',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'e.g., Uganda Field Team',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final service = ref.read(credentialServiceProvider);
                final result = await service.createCredential(
                  projectId: projectId,
                  username: usernameController.text.trim(),
                  description: descriptionController.text.trim(),
                );
                ref.invalidate(credentialsProvider(projectId));
                if (context.mounted) {
                  Navigator.pop(context);
                  _showPasswordDialog(context, result.credential.username,
                      result.password);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showPasswordDialog(
      BuildContext context, String username, String password) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Credentials Created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Save these credentials - the password cannot be retrieved later!'),
            const SizedBox(height: 16),
            SelectableText('Username: $username'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: SelectableText('Password: $password')),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: password));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password copied')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _handleCredentialAction(BuildContext context, WidgetRef ref,
      AppCredential cred, String action) async {
    final service = ref.read(credentialServiceProvider);

    switch (action) {
      case 'activate':
        await service.activateCredential(cred.id);
        break;
      case 'deactivate':
        await service.deactivateCredential(cred.id);
        break;
      case 'regenerate':
        final newPassword = await service.regeneratePassword(cred.id);
        if (context.mounted) {
          _showPasswordDialog(context, cred.username, newPassword);
        }
        break;
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Credential'),
            content:
                Text('Are you sure you want to delete "${cred.username}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await service.deleteCredential(cred.id);
        }
        break;
    }

    ref.invalidate(credentialsProvider(projectId));
  }
}
```

### Step 9.5: Checklist

- [ ] Team service created
- [ ] Credential service created
- [ ] Team provider created
- [ ] Team tab with members subtab
- [ ] Team tab with credentials subtab
- [ ] Member invitation working
- [ ] Credential creation working
- [ ] Credential management working

---

## Phase 10: Web App - Data Viewing

**Estimated time: 3-4 hours**

### Step 10.1: Create Submission Model

**lib/models/submission.dart:**

```dart
class Submission {
  final String id;
  final String projectId;
  final String? surveyPackageId;
  final String? crfId;
  final String tableName;
  final String? recordId;
  final String localUniqueId;
  final Map<String, dynamic> data;
  final int version;
  final String? parentTable;
  final String? parentRecordId;
  final String? deviceId;
  final String? surveyorId;
  final String? appVersion;
  final DateTime? collectedAt;
  final DateTime submittedAt;
  final DateTime updatedAt;

  Submission({
    required this.id,
    required this.projectId,
    this.surveyPackageId,
    this.crfId,
    required this.tableName,
    this.recordId,
    required this.localUniqueId,
    required this.data,
    this.version = 1,
    this.parentTable,
    this.parentRecordId,
    this.deviceId,
    this.surveyorId,
    this.appVersion,
    this.collectedAt,
    required this.submittedAt,
    required this.updatedAt,
  });

  factory Submission.fromJson(Map<String, dynamic> json) {
    return Submission(
      id: json['id'],
      projectId: json['project_id'],
      surveyPackageId: json['survey_package_id'],
      crfId: json['crf_id'],
      tableName: json['table_name'],
      recordId: json['record_id'],
      localUniqueId: json['local_unique_id'],
      data: json['data'] ?? {},
      version: json['version'] ?? 1,
      parentTable: json['parent_table'],
      parentRecordId: json['parent_record_id'],
      deviceId: json['device_id'],
      surveyorId: json['surveyor_id'],
      appVersion: json['app_version'],
      collectedAt: json['collected_at'] != null
          ? DateTime.parse(json['collected_at'])
          : null,
      submittedAt: DateTime.parse(json['submitted_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  /// Get a field value from data
  dynamic operator [](String key) => data[key];
}
```

### Step 10.2: Create Submission Service

**lib/services/submission_service.dart:**

```dart
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/submission.dart';
import '../models/crf.dart';

class SubmissionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Get submissions for a project and table
  Future<List<Submission>> getSubmissions({
    required String projectId,
    required String tableName,
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _supabase
        .from('submissions')
        .select()
        .eq('project_id', projectId)
        .eq('table_name', tableName)
        .order('collected_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List).map((s) => Submission.fromJson(s)).toList();
  }

  /// Get submission count
  Future<int> getSubmissionCount({
    required String projectId,
    required String tableName,
  }) async {
    final response = await _supabase
        .from('submissions')
        .select('id')
        .eq('project_id', projectId)
        .eq('table_name', tableName)
        .count(CountOption.exact);

    return response.count ?? 0;
  }

  /// Get submission counts by table
  Future<Map<String, int>> getSubmissionCountsByTable(String projectId) async {
    final response = await _supabase
        .from('submissions')
        .select('table_name')
        .eq('project_id', projectId);

    final counts = <String, int>{};
    for (final row in response as List) {
      final tableName = row['table_name'] as String;
      counts[tableName] = (counts[tableName] ?? 0) + 1;
    }
    return counts;
  }

  /// Get submissions by surveyor
  Future<Map<String, int>> getSubmissionsBySurveyor(String projectId) async {
    final response = await _supabase
        .from('submissions')
        .select('surveyor_id')
        .eq('project_id', projectId);

    final counts = <String, int>{};
    for (final row in response as List) {
      final surveyorId = row['surveyor_id'] as String? ?? 'Unknown';
      counts[surveyorId] = (counts[surveyorId] ?? 0) + 1;
    }
    return counts;
  }

  /// Export submissions to CSV
  String exportToCsv({
    required List<Submission> submissions,
    required List<CrfField> fields,
  }) {
    if (submissions.isEmpty) return '';

    final buffer = StringBuffer();

    // Header row
    final headers = [
      'record_id',
      ...fields.map((f) => f.fieldName),
      'collected_at',
      'surveyor_id',
    ];
    buffer.writeln(headers.map((h) => '"$h"').join(','));

    // Data rows
    for (final submission in submissions) {
      final values = [
        submission.recordId ?? '',
        ...fields.map((f) => submission.data[f.fieldName]?.toString() ?? ''),
        submission.collectedAt?.toIso8601String() ?? '',
        submission.surveyorId ?? '',
      ];
      buffer.writeln(values.map((v) => '"${v.replaceAll('"', '""')}"').join(','));
    }

    return buffer.toString();
  }
}
```

### Step 10.3: Create Submission Provider

**lib/providers/submission_provider.dart:**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/submission.dart';
import '../services/submission_service.dart';

final submissionServiceProvider =
    Provider<SubmissionService>((ref) => SubmissionService());

class SubmissionQuery {
  final String projectId;
  final String tableName;

  SubmissionQuery({required this.projectId, required this.tableName});

  @override
  bool operator ==(Object other) =>
      other is SubmissionQuery &&
      other.projectId == projectId &&
      other.tableName == tableName;

  @override
  int get hashCode => Object.hash(projectId, tableName);
}

final submissionsProvider =
    FutureProvider.family<List<Submission>, SubmissionQuery>((ref, query) async {
  final service = ref.watch(submissionServiceProvider);
  return await service.getSubmissions(
    projectId: query.projectId,
    tableName: query.tableName,
  );
});

final submissionCountsProvider =
    FutureProvider.family<Map<String, int>, String>((ref, projectId) async {
  final service = ref.watch(submissionServiceProvider);
  return await service.getSubmissionCountsByTable(projectId);
});
```

### Step 10.4: Update Data Tab

**lib/screens/dashboard/data_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/submission_provider.dart';
import '../../providers/survey_provider.dart';
import '../../models/crf.dart';

class DataTab extends ConsumerStatefulWidget {
  final String projectId;

  const DataTab({super.key, required this.projectId});

  @override
  ConsumerState<DataTab> createState() => _DataTabState();
}

class _DataTabState extends ConsumerState<DataTab> {
  String? _selectedTable;
  final _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final countsAsync = ref.watch(submissionCountsProvider(widget.projectId));

    return countsAsync.when(
      data: (counts) {
        if (counts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No data yet',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
                const SizedBox(height: 8),
                const Text('Data will appear here when collected via the app'),
              ],
            ),
          );
        }

        final tables = counts.keys.toList()..sort();
        _selectedTable ??= tables.first;

        return Column(
          children: [
            // Table selector and stats
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedTable,
                      decoration: const InputDecoration(
                        labelText: 'Select Form',
                        border: OutlineInputBorder(),
                      ),
                      items: tables.map((table) {
                        return DropdownMenuItem(
                          value: table,
                          child: Text('$table (${counts[table]} records)'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedTable = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () => _exportData(context, ref),
                    icon: const Icon(Icons.download),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
            ),

            // Data table
            Expanded(
              child: _selectedTable != null
                  ? _DataTable(
                      projectId: widget.projectId,
                      tableName: _selectedTable!,
                    )
                  : const SizedBox(),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _exportData(BuildContext context, WidgetRef ref) {
    // TODO: Implement CSV export
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export coming soon')),
    );
  }
}

class _DataTable extends ConsumerWidget {
  final String projectId;
  final String tableName;

  const _DataTable({required this.projectId, required this.tableName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = SubmissionQuery(projectId: projectId, tableName: tableName);
    final submissionsAsync = ref.watch(submissionsProvider(query));
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');

    return submissionsAsync.when(
      data: (submissions) {
        if (submissions.isEmpty) {
          return const Center(child: Text('No records in this form'));
        }

        // Get all unique field names from data
        final allFields = <String>{};
        for (final s in submissions) {
          allFields.addAll(s.data.keys);
        }
        final fields = allFields.toList()..sort();

        // Limit columns for display
        final displayFields = fields.take(5).toList();

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Record ID')),
                ...displayFields.map((f) => DataColumn(label: Text(f))),
                const DataColumn(label: Text('Collected')),
                const DataColumn(label: Text('Surveyor')),
              ],
              rows: submissions.map((s) {
                return DataRow(
                  cells: [
                    DataCell(Text(s.recordId ?? s.localUniqueId)),
                    ...displayFields.map((f) {
                      final value = s.data[f];
                      return DataCell(Text(
                        value?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ));
                    }),
                    DataCell(Text(
                      s.collectedAt != null
                          ? dateFormat.format(s.collectedAt!)
                          : '',
                    )),
                    DataCell(Text(s.surveyorId ?? '')),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
```

### Step 10.5: Update Reports Tab

**lib/screens/dashboard/reports_tab.dart:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/submission_provider.dart';

class ReportsTab extends ConsumerWidget {
  final String projectId;

  const ReportsTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsAsync = ref.watch(submissionCountsProvider(projectId));

    return countsAsync.when(
      data: (counts) {
        final totalRecords = counts.values.fold(0, (a, b) => a + b);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Total Records',
                      value: totalRecords.toString(),
                      icon: Icons.assignment,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      title: 'Forms',
                      value: counts.length.toString(),
                      icon: Icons.list_alt,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Records by form
              Text(
                'Records by Form',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: counts.entries.map((entry) {
                    return ListTile(
                      title: Text(entry.key),
                      trailing: Text(
                        entry.value.toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 10.6: Checklist

- [ ] Submission model created
- [ ] Submission service created
- [ ] Submission provider created
- [ ] Data tab shows submissions
- [ ] Table selector works
- [ ] Reports tab shows statistics
- [ ] CSV export (basic implementation)

---

## Phases 11-15: Mobile App Updates

I'll continue with the mobile app phases in the next section of the document due to length.

See **GISTKOLLECT_IMPLEMENTATION_PLAN_PART3.md** for:
- Phase 11: Mobile App - Rename & Rebrand
- Phase 12: Mobile App - Authentication
- Phase 13: Mobile App - Survey Download
- Phase 14: Mobile App - Data Sync
- Phase 15: Testing & Deployment

---

*Document continues in Part 3...*
