import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../utils/phone_format.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/login_page.dart';
import '../../components/bottom_fade.dart';
import '../../components/custom_loader.dart';
import '../../constants/app_images.dart';
import 'addresses_section.dart';
import 'rewards.dart';
import 'create_new_card.dart';
import 'coupons_section.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _currentIndex = 0;


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

  void _navigateToSettings() {
    setState(() => _currentIndex = 0);
  }

  Future<void> _fetchUserName() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (userDoc.exists) {
          setState(() {
            _nameController.text =
                userDoc.data()?['userInfo']['name'] ?? 'Usuario';
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error al obtener el nombre del usuario: $e');
      }
    }
  }

  Future<void> _fetchUserData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
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
          _phoneNumberController.text =
              formatMxPhone(userInfoDoc.data()?['phoneNumber'] ?? '');
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error al obtener los datos del usuario: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateUserInfo(String field, String value) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        if (field == 'phoneNumber') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('userInfo')
              .doc('userInfo')
              .update({field: value});
        }
        if (!mounted) return;
        _showAlertDialog('Éxito', 'Información actualizada con éxito');
      } catch (e) {
        if (kDebugMode) debugPrint('Error al actualizar la información: $e');
        if (!mounted) return;
        _showAlertDialog('Error', 'Error al actualizar la información');
      }
    }
  }

  Future<void> _changePassword(String password) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePassword(password);
        _passwordController.clear();
        _confirmPasswordController.clear();
        if (!mounted) return;
        _showAlertDialog('Éxito', 'Contraseña actualizada con éxito');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error al cambiar la contraseña: $e');
      if (!mounted) return;

      String errorMsg = 'Error al cambiar la contraseña';
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        errorMsg = 'Esta operación es sensible y requiere un inicio de sesión reciente. Por favor, vuelve a iniciar sesión e intenta de nuevo.';
      }
      _showAlertDialog('Error', errorMsg);
    }
  }

  Future<void> _deleteUserFirestoreData(String userId) async {
    final firestore = FirebaseFirestore.instance;
    final userDocRef = firestore.collection('users').doc(userId);

    final subcollections = ['rewardsCard', 'userInfo', 'addresses', 'orderHistory', 'coupons'];
    for (final sub in subcollections) {
      final snapshot = await userDocRef.collection(sub).get();
      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      if (snapshot.docs.isNotEmpty) {
        await batch.commit();
      }
    }

    await userDocRef.delete();
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Cuenta'),
        content: const Text(
            '¿Estás seguro de que deseas eliminar tu cuenta y todos tus datos? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _deleteUserFirestoreData(user.uid);
        await user.delete();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
              (route) => false,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Error al eliminar la cuenta: $e');
        if (!mounted) return;
        _showAlertDialog('Error',
            'No se pudo eliminar la cuenta. Es posible que debas volver a iniciar sesión para confirmar esta acción.');
      }
    }
  }

  void _handleChangePassword() {
    if (_passwordController.text.isEmpty) return;

    if (_formKey.currentState?.validate() ?? false) {
      _changePassword(_passwordController.text);
    }
  }

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
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  String? _validatePhoneNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return 'Por favor, ingresa tu número de teléfono';
    }
    if (digits.length != 10) {
      return 'Por favor, ingresa un número de teléfono válido de 10 dígitos';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña no puede estar vacía';
    }
    if (value.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor, confirma tu contraseña';
    }
    if (value != _passwordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  List<Widget> _buildPages() {
    return [
      _buildSettingsContent(),
      AddressesSection(onBack: _navigateToSettings),
      RewardsCardPage(
        onBack: _navigateToSettings,
        onCreateCard: () => setState(() => _currentIndex = 3),
      ),
      // Back from create lands on the rewards page (index 2), not the
      // settings home — the user came from rewards and expects to see
      // their new monedero immediately after creating it.
      CreateNewCard(onBack: () => setState(() => _currentIndex = 2)),
      CouponsSection(onBack: _navigateToSettings),
    ];
  }

  Widget _buildSettingsContent() {
    final user = FirebaseAuth.instance.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    const cardColor = Colors.white;
    const accentColor = Colors.black;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: SizedBox(
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
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Inicia sesión para ver tu configuración',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 16),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text(
                    'Iniciar Sesión',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          _navigateToSettings();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: SizedBox(
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
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
        backgroundColor: Colors.white,
        body: _isLoading
            ? const CustomLoader()
            : BottomFade(
                child: ListView(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 130.0),
          children: [
            _buildHeaderSection(cardColor),
            const SizedBox(height: 20),
            _sectionLabel('Cuenta'),
            Card(
              color: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: ListTile(
                leading: const Icon(Icons.email_outlined, color: accentColor),
                title: const Text(
                  'Correo electrónico',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: accentColor),
                ),
                subtitle: Text(_emailController.text),
              ),
            ),
            const SizedBox(height: 10),
            _buildExpandingInputCard(
              title: 'Número de teléfono',
              controller: _phoneNumberController,
              icon: Icons.phone_android,
              keyboardType: TextInputType.phone,
              inputFormatters: [MxPhoneFormatter()],
              validator: _validatePhoneNumber,
              onSave: () => _updateUserInfo('phoneNumber',
                  _phoneNumberController.text.replaceAll(RegExp(r'\D'), '')),
              cardColor: cardColor,
              accentColor: accentColor,
              tileKey: const Key('phone_tile'),
            ),
            const SizedBox(height: 22),
            _sectionLabel('Seguridad'),
            _buildPasswordExpansionTile(
              cardColor: cardColor,
              accentColor: accentColor,
            ),
            const SizedBox(height: 22),
            _sectionLabel('Compras y recompensas'),
            _buildExpansionOption(
              title: 'Cochinito',
              icon: Icons.savings_outlined,
              accentColor: accentColor,
              cardColor: cardColor,
              onTap: () {
                setState(() {
                  _currentIndex = 2;
                });
              },
            ),
            const SizedBox(height: 10),
            _buildExpansionOption(
              title: 'Cupones',
              icon: Icons.confirmation_number_outlined,
              accentColor: accentColor,
              cardColor: cardColor,
              onTap: () {
                setState(() {
                  _currentIndex = 4;
                });
              },
            ),
            const SizedBox(height: 10),
            _buildExpansionOption(
              title: 'Domicilio',
              icon: Icons.location_on_outlined,
              accentColor: accentColor,
              cardColor: cardColor,
              onTap: () => setState(() => _currentIndex = 1),
            ),
          ],
                ),
              ),
      ),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  Widget _buildHeaderSection(Color cardColor) {
    return _FlipCard(
      front: _headerFront(cardColor),
      back: _headerBack(cardColor),
    );
  }

  Widget _headerFront(Color cardColor) {
    return Stack(
      children: [
        Container(
          height: 155,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bienvenido,',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              Text(
                _nameController.text.isEmpty ? 'Usuario' : _nameController.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87),
              ),
              const SizedBox(height: 12),
              Divider(color: Colors.grey[400], thickness: 1),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filipenses 1:9-10',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  Icon(Icons.touch_app_outlined,
                      size: 18, color: Colors.grey[500]),
                ],
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
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.error, color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerBack(Color cardColor) {
    return Container(
      height: 170,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Cerrar sesión',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _deleteAccount,
              icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
              label: const Text('Eliminar cuenta',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandingInputCard({
    required String title,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    List<TextInputFormatter>? inputFormatters,
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
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: tileKey,
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
                        inputFormatters: inputFormatters,
                        validator: validator,
                        decoration: InputDecoration(
                          hintText: 'Ingresa $title',
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 50,
                      child: ElevatedButton(
                        onPressed: onSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.zero,
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
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
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
              child: Form(
                key: _formKey,
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
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
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
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
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
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }


  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Colors.grey[500],
        ),
      ),
    );
  }

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

class _FlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  const _FlipCard({required this.front, required this.back});

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  void _flip() {
    if (_controller.isAnimating) return;
    if (_controller.value == 0) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double angle = _controller.value * math.pi;
          final bool showBack = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: showBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: widget.back,
                  )
                : widget.front,
          );
        },
      ),
    );
  }
}
