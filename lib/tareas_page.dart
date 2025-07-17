import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:typed_data';

class TareasPage extends StatefulWidget {
  const TareasPage({super.key});

  @override
  State<TareasPage> createState() => _TareasPageState();
}

class _TareasPageState extends State<TareasPage> {
  final supabase = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _imagePicker = ImagePicker();
  
  List<Map<String, dynamic>> _tareas = [];
  List<Map<String, dynamic>> _tareasCompartidas = [];
  bool _isLoading = false;
  Uint8List? _selectedImageBytes;
  DateTime _selectedDate = DateTime.now();
  String _selectedStatus = 'pendiente';
  String _selectedCollection = 'personal'; // 'personal' o 'compartida'

  @override
  void initState() {
    super.initState();
    _loadTareas();
    _loadTareasCompartidas();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadTareas() async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('tareas')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _tareas = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      _showError('Error al cargar tareas: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTareasCompartidas() async {
    try {
      final response = await supabase
          .from('tareas_compartidas')
          .select('*')
          .order('created_at', ascending: false);

      setState(() {
        _tareasCompartidas = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      _showError('Error al cargar tareas compartidas: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      _showError('Error al seleccionar imagen: $e');
    }
  }

  Future<String?> _uploadImage(Uint8List imageBytes, String fileName) async {
    try {
      final String path = 'tareas/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      await supabase.storage
          .from('tareas-images')
          .uploadBinary(path, imageBytes);

      final String publicUrl = supabase.storage
          .from('tareas-images')
          .getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      _showError('Error al subir imagen: $e');
      return null;
    }
  }

  Future<void> _createTarea() async {
    if (_titleController.text.trim().isEmpty) {
      _showError('El título es obligatorio');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _showError('Usuario no autenticado');
        return;
      }

      String? imageUrl;
      if (_selectedImageBytes != null) {
        final fileName = 'tarea_${DateTime.now().millisecondsSinceEpoch}.jpg';
        imageUrl = await _uploadImage(_selectedImageBytes!, fileName);
      }

      final tableName = _selectedCollection == 'compartida' ? 'tareas_compartidas' : 'tareas';
      final userField = _selectedCollection == 'compartida' ? 'created_by' : 'user_id';

      await supabase.from(tableName).insert({
        'titulo': _titleController.text.trim(),
        'estado': _selectedStatus,
        'imagen_url': imageUrl,
        'fecha_publicacion': _selectedDate.toIso8601String(),
        userField: user.id,
        'created_at': DateTime.now().toIso8601String(),
      });

      _clearForm();
      
      // Recargar ambas listas para mostrar los cambios
      await _loadTareas();
      await _loadTareasCompartidas();
      
      Navigator.of(context).pop();
      
      final collectionName = _selectedCollection == 'compartida' ? 'compartidas' : 'personales';
      _showSuccess('Tarea creada exitosamente en $collectionName');
    } catch (e) {
      _showError('Error al crear tarea: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateTareaStatus(String tareaId, String newStatus, {bool isShared = false}) async {
    try {
      final tableName = isShared ? 'tareas_compartidas' : 'tareas';
      
      final updateData = {'estado': newStatus};
      
      // Si es una tarea compartida y se está completando, registrar quién la completó
      if (isShared && newStatus == 'completada') {
        final user = supabase.auth.currentUser;
        if (user != null) {
          updateData['completed_by'] = user.id;
          updateData['completed_at'] = DateTime.now().toIso8601String();
        }
      }
      
      await supabase
          .from(tableName)
          .update(updateData)
          .eq('id', tareaId);

      // Recargar ambas listas para mostrar los cambios
      await _loadTareas();
      if (isShared) {
        await _loadTareasCompartidas();
      }
      
      final tipoTarea = isShared ? 'compartida' : 'personal';
      _showSuccess('Tarea $tipoTarea actualizada');
    } catch (e) {
      _showError('Error al actualizar tarea: $e');
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      final TimeOfDay? timePicked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );

      if (timePicked != null) {
        setState(() {
          _selectedDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            timePicked.hour,
            timePicked.minute,
          );
        });
      }
    }
  }

  void _clearForm() {
    _titleController.clear();
    setState(() {
      _selectedImageBytes = null;
      _selectedDate = DateTime.now();
      _selectedStatus = 'pendiente';
      _selectedCollection = 'personal';
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showImageSourceDialog(StateSetter setDialogState) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Seleccionar imagen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _pickImage(ImageSource.camera);
                  setDialogState(() {}); // Actualizar el diálogo principal
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Seleccionar de galería'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _pickImage(ImageSource.gallery);
                  setDialogState(() {}); // Actualizar el diálogo principal
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateTareaDialog({String? preselectedCollection}) {
    _clearForm();
    if (preselectedCollection != null) {
      _selectedCollection = preselectedCollection;
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Text('Nueva Tarea'),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedCollection == 'compartida' ? Colors.blue : Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _selectedCollection == 'compartida' ? 'Compartida' : 'Personal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título de la tarea',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'pendiente', child: Text('Pendiente')),
                        DropdownMenuItem(value: 'completada', child: Text('Completada')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedStatus = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedCollection,
                      decoration: const InputDecoration(
                        labelText: 'Guardar en',
                        border: OutlineInputBorder()
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'personal', 
                          child: Row(
                            children: [
                              SizedBox(width: 8),
                              Text('Mis Tareas'),
                              SizedBox(width: 8),
                              Text('(Solo yo puedo verla)', 
                                style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'compartida', 
                          child: Row(
                            children: [
                              SizedBox(width: 8),
                              Text('Tareas Compartidas'),
                              SizedBox(width: 8),
                              Text('(Todos pueden verla)', 
                                style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _selectedCollection = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: Text('Fecha y hora'),
                        subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(_selectedDate)),
                        onTap: () async {
                          await _selectDate();
                          setDialogState(() {});
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: Icon(
                          _selectedImageBytes != null ? Icons.image : Icons.image,
                          color: _selectedImageBytes != null ? Colors.green : null,
                        ),
                        title: const Text('Imagen de la tarea'),
                        subtitle: _selectedImageBytes != null 
                            ? Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  const SizedBox(width: 4),
                                  const Text('Imagen seleccionada'),
                                ],
                              )
                            : const Text('Sin imagen'),
                        trailing: _selectedImageBytes != null 
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        _selectedImageBytes = null;
                                      });
                                    },
                                  ),
                                  const Icon(Icons.add_a_photo),
                                ],
                              )
                            : const Icon(Icons.add_a_photo),
                        onTap: () => _showImageSourceDialog(setDialogState),
                      ),
                    ),
                    if (_selectedImageBytes != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _selectedImageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _createTarea,
                  child: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crear Tarea'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTareaCard(Map<String, dynamic> tarea, {bool isShared = false}) {
    final DateTime? fechaPublicacion = tarea['fecha_publicacion'] != null 
        ? DateTime.tryParse(tarea['fecha_publicacion']) 
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    tarea['titulo'] ?? 'Sin título',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: tarea['estado'] == 'completada' 
                        ? Colors.green 
                        : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tarea['estado'] ?? 'pendiente',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (fechaPublicacion != null)
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(fechaPublicacion),
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            if (tarea['imagen_url'] != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  tarea['imagen_url'],
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: Colors.grey[300],
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 50),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (tarea['estado'] != 'completada') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _updateTareaStatus(tarea['id'], 'completada', isShared: isShared),
                  icon: const Icon(Icons.check),
                  label: Text(isShared ? 'Marcar como completada (Compartida)' : 'Marcar como completada'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isShared ? Colors.blue : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestión de Tareas'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mis Tareas'),
              Tab(text: 'Compartidas'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: () async {
                await supabase.auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
              onRefresh: _loadTareas,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _tareas.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.refresh, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No tienes tareas aún',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Toca el botón + para crear una nueva tarea',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _tareas.length,
                          itemBuilder: (context, index) {
                            return _buildTareaCard(_tareas[index]);
                          },
                        ),
            ),
            RefreshIndicator(
              onRefresh: _loadTareasCompartidas,
              child: _tareasCompartidas.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No hay tareas compartidas',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _tareasCompartidas.length,
                      itemBuilder: (context, index) {
                        return _buildTareaCard(_tareasCompartidas[index], isShared: true);
                      },
                    ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCreateTareaDialog(),
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}
