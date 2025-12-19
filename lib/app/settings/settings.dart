import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/login_page.dart';
import '../../components/custom_loader.dart';
import '../../constants/app_images.dart';
import '../../main.dart';
import 'addresses_section.dart';
import 'rewards.dart';
import 'create_new_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _currentIndex = 0; // 0 para la vista de Configuración

  // Controladores y variables para la información personal
  late TextEditingController _emailController;
  late TextEditingController _phoneNumberController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  late TextEditingController _nameController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneNumberController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    _fetchUserName();
    _fetchUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneNumberController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // Navegar de regreso a la vista de Configuración
  void _navigateToSettings() {
    setState(() {
      _currentIndex = 0;
    });
  }

  // Obtener el nombre del usuario desde Firebase
  Future<void> _fetchUserName() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
        if (userDoc.exists) {
          setState(() {
            _nameController.text = userDoc.data()?['userInfo']['name'] ?? 'Usuario';
          });
        }
      } catch (e) {
        print('Error al obtener el nombre del usuario: $e');
      }
    }
  }

  // Obtener datos del usuario (correo electrónico, teléfono)
  Future<void> _fetchUserData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userInfoDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('userInfo')
          .doc('userInfo')
          .get();

      if (userDoc.exists) {
        setState(() {
          _emailController.text = userDoc.data()?['userInfo']['email'] ?? '';
          _nameController.text = userDoc.data()?['userInfo']['name'] ?? '';
        });
      }

      if (userInfoDoc.exists) {
        setState(() {
          _phoneNumberController.text = userInfoDoc.data()?['phoneNumber'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error al obtener los datos del usuario: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Actualizar información del usuario
  Future<void> _updateUserInfo(String field, String value) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        if (field == 'email') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'userInfo.$field': value,
          });
        } else if (field == 'phoneNumber') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('userInfo')
              .doc('userInfo')
              .update({field: value});
        }
        // Show success dialog
        _showAlertDialog('Éxito', 'Información actualizada con éxito');
      } catch (e) {
        print('Error al actualizar la información: $e');
        // Show error dialog
        _showAlertDialog('Error', 'Error al actualizar la información');
      }
    }
  }

  // Cambiar contraseña
  Future<void> _changePassword(String password) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePassword(password);
        _passwordController.clear();
        _confirmPasswordController.clear();
        // Show success dialog
        _showAlertDialog('Éxito', 'Contraseña actualizada con éxito');
      }
    } catch (e) {
      print('Error al cambiar la contraseña: $e');
      // Show error dialog
      _showAlertDialog('Error', 'Error al cambiar la contraseña');
    }
  }

  void _handleChangePassword() {
    if (_passwordController.text.isEmpty) {
      // No se solicitó cambio de contraseña
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      _changePassword(_passwordController.text);
    }
  }

  // Método para mostrar AlertDialog
  void _showAlertDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('Aceptar'),
              onPressed: () {
                Navigator.of(context).pop(); // Cerrar el diálogo
              },
            ),
          ],
        );
      },
    );
  }

  // Validaciones
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor, ingresa tu correo electrónico';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) {
      return 'Por favor, ingresa un correo electrónico válido';
    }
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor, ingresa tu número de teléfono';
    }
    final phoneRegex = RegExp(r'^\+?\d{10,15}$');
    if (!phoneRegex.hasMatch(value)) {
      return 'Por favor, ingresa un número de teléfono válido';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value != null && value.isNotEmpty && value.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (_passwordController.text.isNotEmpty) {
      if (value == null || value.isEmpty) {
        return 'Por favor, confirma tu contraseña';
      }
      if (value != _passwordController.text) {
        return 'Las contraseñas no coinciden';
      }
    }
    return null;
  }

  // Lista de páginas correspondientes a cada índice
  List<Widget> _buildPages() {
    return [
      _buildSettingsContent(),
      AddressesSection(
        onBack: _navigateToSettings,
      ),
      RewardsCardPage(
        onBack: _navigateToSettings,
      ),
      CreateNewCard(
        onBack: _navigateToSettings,
      ),
    ];
  }

  // Contenido principal de Configuración
  Widget _buildSettingsContent() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? Colors.white : Colors.white;
    final accentColor = Colors.black; // Ajusta el color según sea necesario

    return WillPopScope(
      onWillPop: () async {
        if (_currentIndex != 0) {
          _navigateToSettings();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Padding(
            padding: const EdgeInsets.all(0),
            child: SizedBox(
              height: 180,
              width: 300,
              child: AspectRatio(
                aspectRatio: 1 / 1,
                child: Image.asset(
                  isDarkMode ? AppImages.logowhite : AppImages.logo,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        backgroundColor: Colors.white,
        body: _isLoading
        // NEW: Use CustomLoader instead of CircularProgressIndicator
            ? const CustomLoader()
            : ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildHeaderSection(cardColor),
            const SizedBox(height: 24),
            _buildExpandingInputCard(
              title: 'Correo electrónico',
              controller: _emailController,
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              onSave: () => _updateUserInfo('email', _emailController.text),
              cardColor: cardColor,
              accentColor: accentColor,
              tileKey: const Key('email_tile'),
            ),
            const SizedBox(height: 10),
            _buildExpandingInputCard(
              title: 'Número de teléfono',
              controller: _phoneNumberController,
              icon: Icons.phone_android,
              keyboardType: TextInputType.phone,
              validator: _validatePhoneNumber,
              onSave: () =>
                  _updateUserInfo('phoneNumber', _phoneNumberController.text),
              cardColor: cardColor,
              accentColor: accentColor,
              tileKey: const Key('phone_tile'),
            ),
            const SizedBox(height: 10),
            _buildPasswordExpansionTile(
              cardColor: cardColor,
              accentColor: accentColor,
            ),
            const SizedBox(height: 10),

            // Domicilio
            _buildExpansionOption(
              title: 'Domicilio',
              icon: Icons.location_on,
              accentColor: accentColor,
              cardColor: cardColor,
              onTap: () {
                setState(() {
                  _currentIndex = 1; // Cambiar a la sección de Direcciones
                });
              },
            ),
            const SizedBox(height: 10),

            // Monedero
            _buildExpansionOption(
              title: 'Monedero',
              icon: Icons.card_membership,
              accentColor: accentColor,
              cardColor: cardColor,
              onTap: () {
                setState(() {
                  _currentIndex = 2; // Cambiar a la página de Monedero
                });
              },
            ),

            // Logout Button (Added Below Monedero)
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.logout, color: accentColor),
              title: Text(
                'Cerrar sesión',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pushReplacement(customPageRouteBuilder(const LoginPage()));
              },
            ),
          ],
        ),
      ),
    );
  }


  // Método para construir la sección de encabezado
  Widget _buildHeaderSection(Color cardColor) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20,30, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bienvenido,',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              Text(
                _nameController.text.isEmpty ? 'Usuario' : _nameController.text,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              Divider(color: Colors.grey[400], thickness: 1),
              Text(
                'Filipenses 1:9-10',
                style: TextStyle(
                  fontSize: 14, // Smaller font size for subtlety
                  color: Colors.grey[600], // Subdued color for elegance
                  fontStyle: FontStyle.italic, // Italic style for emphasis
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: SizedBox(
            width: 100,
            height: 100,
            child: Lottie.asset(
              'assets/animations/animation.json',
              repeat: true,
              animate: true,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.error, color: Colors.red);
              },
            ),
          ),
        ),
      ],
    );
  }

  // Método para construir los campos de entrada expandibles
  Widget _buildExpandingInputCard({
    required String title,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    required String? Function(String?) validator,
    required VoidCallback onSave,
    required Color cardColor,
    required Color accentColor,
    Key? tileKey,
  }) {
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 6,
      shadowColor: Colors.black26,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent, // Eliminar efecto de salpicadura
          highlightColor: Colors.transparent, // Eliminar efecto de resaltado
        ),
        child: ExpansionTile(
          key: tileKey, // Clave única
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
          childrenPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
          trailing: const Icon(Icons.expand_more, color: Colors.black54),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        obscureText: isPassword,
                        keyboardType: keyboardType,
                        validator: validator,
                        decoration: InputDecoration(
                          hintText: 'Ingresa $title',
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding:
                          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 50, // Ajusta el ancho según sea necesario
                      child: ElevatedButton(
                        onPressed: onSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.zero, // Eliminar padding interno
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordExpansionTile({
    required Color cardColor,
    required Color accentColor,
  }) {
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      shadowColor: Colors.black26,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent, // Eliminar efecto de salpicadura
          highlightColor: Colors.transparent, // Eliminar efecto de resaltado
        ),
        child: ExpansionTile(
          key: const Key('password_tile'),
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
          childrenPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: accentColor),
              const SizedBox(width: 10),
              Text(
                'Cambiar contraseña',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
          trailing: const Icon(Icons.expand_more, color: Colors.black54),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8),
              child: Column(
                children: [
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    validator: _validatePassword,
                    decoration: InputDecoration(
                      hintText: 'Nueva contraseña',
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    validator: _validateConfirmPassword,
                    decoration: InputDecoration(
                      hintText: 'Confirmar contraseña',
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleChangePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Actualizar contraseña',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Nuevo método para construir las opciones de Domicilio y Monedero como ExpansionTile
  Widget _buildExpansionOption({
    required String title,
    required IconData icon,
    required Color accentColor,
    required Color cardColor,
    required VoidCallback onTap,
  }) {
    return Card(
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      shadowColor: Colors.black26,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16.0),
          title: Row(
            children: [
              Icon(icon, color: accentColor),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
          trailing: const Icon(Icons.expand_more, color: Colors.black54),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Administrar $title',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentIndex,
      children: _buildPages(),
    );
  }
}
