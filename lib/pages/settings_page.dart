import 'package:flutter/material.dart';
import '../models/environment_config.dart';
import '../services/environment_service.dart';

class SettingsPage extends StatefulWidget {
  final EnvironmentService envService;

  const SettingsPage({super.key, required this.envService});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late List<EnvironmentConfig> _environments;
  String? _activeEnv;

  @override
  void initState() {
    super.initState();
    _environments = widget.envService.getEnvironments();
    _activeEnv = widget.envService.getActiveEnvironment();
  }

  Future<void> _saveAndRefresh() async {
    await widget.envService.saveEnvironments(_environments);
    setState(() {});
  }

  void _addEnvironment() {
    _showEnvironmentDialog(null);
  }

  void _editEnvironment(int index) {
    _showEnvironmentDialog(index);
  }

  void _deleteEnvironment(int index) async {
    final env = _environments[index];
    _environments.removeAt(index);
    if (_activeEnv == env.name) {
      _activeEnv = _environments.isNotEmpty ? _environments.first.name : null;
      if (_activeEnv != null) {
        await widget.envService.setActiveEnvironment(_activeEnv!);
      }
    }
    await _saveAndRefresh();
  }

  void _setActive(String name) async {
    _activeEnv = name;
    await widget.envService.setActiveEnvironment(name);
    setState(() {});
  }

  void _showEnvironmentDialog(int? editIndex) {
    final isEdit = editIndex != null;
    final existing = isEdit ? _environments[editIndex] : null;

    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(text: existing?.baseUrl ?? '');
    final tenantController = TextEditingController(text: existing?.tenant ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Environment' : 'Add Environment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Production, Staging, Dev',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://your-ls-central-server.com',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tenantController,
                decoration: const InputDecoration(
                  labelText: 'Tenant (optional)',
                  hintText: 'e.g. default',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final url = urlController.text.trim();
              if (name.isEmpty || url.isEmpty) return;

              if (isEdit) {
                _environments[editIndex] = EnvironmentConfig(
                  name: name,
                  baseUrl: url,
                  tenant: tenantController.text.trim(),
                );
              } else {
                _environments.add(EnvironmentConfig(
                  name: name,
                  baseUrl: url,
                  tenant: tenantController.text.trim(),
                ));
              }

              if (_activeEnv == null) {
                _activeEnv = name;
                await widget.envService.setActiveEnvironment(name);
              }

              await _saveAndRefresh();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEnvironment,
        child: const Icon(Icons.add),
      ),
      body: _environments.isEmpty
          ? const Center(
              child: Text(
                'No environments configured.\nTap + to add one.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _environments.length,
              itemBuilder: (context, index) {
                final env = _environments[index];
                final isActive = env.name == _activeEnv;
                return Card(
                  elevation: isActive ? 3 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isActive
                        ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(
                      isActive ? Icons.check_circle : Icons.circle_outlined,
                      color: isActive ? Theme.of(context).colorScheme.primary : Colors.grey,
                    ),
                    title: Text(
                      env.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(env.baseUrl),
                        if (env.tenant.isNotEmpty) Text('Tenant: ${env.tenant}'),
                      ],
                    ),
                    onTap: () => _setActive(env.name),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _editEnvironment(index);
                        if (value == 'delete') _deleteEnvironment(index);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
