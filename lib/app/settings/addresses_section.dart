import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

import '../../components/bottom_fade.dart';
import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';
import '../../constants/colima_colonias.dart';

class AddressesSection extends StatefulWidget {
  final VoidCallback onBack;
  const AddressesSection({super.key, required this.onBack});

  @override
  State<AddressesSection> createState() => _AddressesSectionState();
}

class _AddressesSectionState extends State<AddressesSection> {
  final _formKey = GlobalKey<FormState>();

  bool _isAddingOrEditing = false;
  String? _editingAddressId;

  final _streetController = TextEditingController();
  final _streetNumberController = TextEditingController();
  final _zipCodeController = TextEditingController();
  String? _selectedColonia;
  final _customColoniaController = TextEditingController();

  final _city = 'Colima';
  final _state = 'Colima';
  LatLng? _selectedLocation;

  String? _resolvedColonia() => _selectedColonia == kOtraColonia
      ? _customColoniaController.text.trim()
      : _selectedColonia;

  @override
  void dispose() {
    _streetController.dispose();
    _streetNumberController.dispose();
    _zipCodeController.dispose();
    _customColoniaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final addressesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('addresses');

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isAddingOrEditing) {
          setState(() {
            _isAddingOrEditing = false;
          });
        } else {
          widget.onBack();
        }
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: addressesRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
                elevation: 0,
              ),
              body: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: 3,
                itemBuilder: (context, index) {
                  return Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerPlaceholder(width: 200, height: 16),
                          SizedBox(height: 8),
                          ShimmerPlaceholder(width: 150, height: 14),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
                elevation: 0,
              ),
              body: Center(
                child: Text(
                  'Error al cargar las direcciones',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            );
          }

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
              backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
              elevation: 0,
              centerTitle: true,
              leading: const SizedBox(),
              iconTheme: const IconThemeData(color: Colors.blueGrey),
              titleTextStyle: const TextStyle(
                color: Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              actions: !_isAddingOrEditing
                  ? [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    icon: const Icon(Icons.add_location_alt,
                        color: Colors.black),
                    onPressed: _startAddingAddress,
                  ),
                ),
              ]
                  : [
                const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    icon: Icon(Icons.add_location_alt,
                        color: Colors.transparent),
                    onPressed: null,
                  ),
                ),
              ],
            ),
            backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
            body: _isAddingOrEditing
                ? _buildAddressForm()
                : snapshot.data!.docs.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No has agregado ninguna dirección.',
                  style: TextStyle(
                    fontSize: 16,
                    color:
                    isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            )
                : BottomFade(
              child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final addressDoc = snapshot.data!.docs[index];
                final address =
                addressDoc.data() as Map<String, dynamic>;
                return AddressExpansionTile(
                  addressId: addressDoc.id,
                  addressData: address,
                  onEdit: () {
                    _startEditingAddress(addressDoc.id, address);
                  },
                  onDelete: () {
                    _confirmDeleteAddress(addressDoc.id);
                  },
                );
              },
            ),
            ),
          );
        },
      ),
    );
  }

  void _startAddingAddress() {
    setState(() {
      _isAddingOrEditing = true;
      _editingAddressId = null;
      _clearFormFields();
    });
  }

  void _startEditingAddress(
      String addressId, Map<String, dynamic> addressData) {
    setState(() {
      _isAddingOrEditing = true;
      _editingAddressId = addressId;
      _populateFormFields(addressData);
    });
  }

  void _clearFormFields() {
    _streetController.clear();
    _streetNumberController.clear();
    _zipCodeController.clear();
    _selectedColonia = null;
    _customColoniaController.clear();
    _selectedLocation = null;
  }

  void _populateFormFields(Map<String, dynamic> addressData) {
    _streetController.text = addressData['street'] ?? '';
    _streetNumberController.text = addressData['streetNumber'] ?? '';
    _zipCodeController.text = addressData['zipCode'] ?? '';
    final colonia = (addressData['colonia'] ?? '').toString();
    final items = coloniasForZip(_zipCodeController.text);
    if (colonia.isNotEmpty && !items.contains(colonia)) {
      _selectedColonia = kOtraColonia;
      _customColoniaController.text = colonia;
    } else {
      _selectedColonia = colonia.isEmpty ? null : colonia;
      _customColoniaController.clear();
    }
    if (addressData['latitude'] != null && addressData['longitude'] != null) {
      _selectedLocation = LatLng(
        addressData['latitude'],
        addressData['longitude'],
      );
    }
  }

  Widget _buildAddressForm() {
    final isEditing = _editingAddressId != null;

    return BottomFade(
      clearHeight: 100,
      fadeHeight: 30,
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
      child: Card(
        elevation: 4.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildTextField(_streetController, 'Calle'),
                    const SizedBox(height: 10),
                    _buildTextField(_streetNumberController, 'Número'),
                    const SizedBox(height: 10),
                    _buildZipField(),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _zipCodeController,
                      builder: (context, _, __) => _buildColoniaField(),
                    ),
                    if (_selectedColonia == kOtraColonia) ...[
                      const SizedBox(height: 10),
                      _buildTextField(
                          _customColoniaController, 'Escribe tu colonia'),
                    ],
                    const SizedBox(height: 10),
                    _buildDisabledField('Ciudad', _city),
                    const SizedBox(height: 10),
                    _buildDisabledField('Estado', _state),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _confirmAddress,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: Text(
                    isEditing ? 'Actualizar Dirección' : 'Confirmar Dirección'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isAddingOrEditing = false;
                  });
                },
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Theme.of(context).primaryColor),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Por favor, ingresa $label';
        }
        return null;
      },
    );
  }

  Widget _buildDisabledField(String label, String value) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      initialValue: value,
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      ),
    );
  }

  Widget _buildZipField() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: _zipCodeController,
      keyboardType: TextInputType.number,
      maxLength: 5,
      decoration: InputDecoration(
        labelText: 'Código Postal',
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Theme.of(context).primaryColor),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Por favor, ingresa el código postal';
        }
        return null;
      },
    );
  }

  Widget _buildColoniaField() {
    final hasZip = _zipCodeController.text.trim().isNotEmpty;
    final items = coloniasForZip(_zipCodeController.text);
    final value = items.contains(_selectedColonia) ? _selectedColonia : null;
    return _buildDropdownField(
      value: value,
      label: hasZip ? 'Colonia' : 'Colonia (ingresa primero el C.P.)',
      items: items,
      onChanged: hasZip
          ? (v) => setState(() {
                _selectedColonia = v;
                if (v != kOtraColonia) _customColoniaController.clear();
              })
          : null,
    );
  }

  Widget _buildDropdownField({
    required String? value,
    required String label,
    required List<String> items,
    required void Function(String?)? onChanged,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      key: ValueKey('dd_${label}_$value'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Theme.of(context).primaryColor),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      ),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Selecciona la colonia (ingresa primero el C.P.)';
        }
        return null;
      },
    );
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
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmAddress() async {
    if (_formKey.currentState!.validate()) {
      final colonia = _resolvedColonia();
      if (colonia == null || colonia.isEmpty) {
        _showAlertDialog('Error', 'Por favor, selecciona o escribe una colonia');
        return;
      }

      final addressString =
          '${_streetController.text} ${_streetNumberController.text}, $colonia, $_city, $_state, ${_zipCodeController.text}, México';

      try {
        List<Location> locations = await locationFromAddress(addressString);
        if (locations.isNotEmpty) {
          final location = locations.first;
          LatLng initialPosition =
          LatLng(location.latitude, location.longitude);

          if (!mounted) return;
          LatLng? selectedPosition = await showDialog<LatLng>(
            context: context,
            builder: (context) => ConfirmLocationDialog(
              initialLocation: _selectedLocation ?? initialPosition,
            ),
          );

          if (selectedPosition != null) {
            _saveAddress(selectedPosition);
          } else {
            _showAlertDialog('Información', 'Ubicación no confirmada');
          }
        } else {
          _showAlertDialog('Error',
              'No se pudo encontrar la ubicación de la dirección');
        }
      } catch (e) {
        _showAlertDialog('Error', 'Error al obtener la ubicación');
      }
    } else {
      _showAlertDialog(
          'Error', 'Por favor, corrige los errores en el formulario');
    }
  }

  void _saveAddress(LatLng position) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final addressesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('addresses');

      final querySnapshot = await addressesRef.get();
      if (querySnapshot.docs.length >= 3 && _editingAddressId == null) {
        _showAlertDialog(
            'Información', 'No puedes agregar más de 3 direcciones');
        return;
      }

      final data = {
        'street': _streetController.text,
        'streetNumber': _streetNumberController.text,
        'colonia': _resolvedColonia(),
        'city': _city,
        'state': _state,
        'zipCode': _zipCodeController.text,
        'country': 'México',
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
      if (_editingAddressId == null) {
        await addressesRef.add(data);
        _showAlertDialog('Éxito', 'Dirección agregada');
      } else {
        await addressesRef.doc(_editingAddressId).update(data);
        _showAlertDialog('Éxito', 'Dirección actualizada');
      }
      setState(() {
        _isAddingOrEditing = false;
      });
    }
  }

  void _confirmDeleteAddress(String addressId) {
    showDialog(
        context: context,
        builder: (context) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: AlertDialog(
              title: const Text('Eliminar Dirección'),
              content: const Text(
                  '¿Estás seguro de que deseas eliminar esta dirección?'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () async {
                    final userId = FirebaseAuth.instance.currentUser?.uid;
                    if (userId != null) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .collection('addresses')
                          .doc(addressId)
                          .delete();
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      _showAlertDialog('Éxito', 'Dirección eliminada');
                    }
                  },
                  child: const Text(
                    'Eliminar',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
        });
  }
}

class ConfirmLocationDialog extends StatefulWidget {
  final LatLng initialLocation;

  const ConfirmLocationDialog({super.key, required this.initialLocation});

  @override
  State<ConfirmLocationDialog> createState() => _ConfirmLocationDialogState();
}

class _ConfirmLocationDialogState extends State<ConfirmLocationDialog> {
  late LatLng _selectedPosition;
  late GoogleMapController _mapController;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          title: const Text('Confirma la ubicación'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _selectedPosition,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              markers: {
                Marker(
                  markerId: const MarkerId('selected'),
                  position: _selectedPosition,
                  draggable: true,
                  onDragEnd: (newPosition) {
                    setState(() {
                      _selectedPosition = newPosition;
                    });
                  },
                ),
              },
              onTap: (position) {
                setState(() {
                  _selectedPosition = position;
                });
                _mapController.animateCamera(CameraUpdate.newLatLng(position));
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(null);
              },
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(_selectedPosition);
              },
              child: const Text('Confirmar Ubicación'),
            ),
          ],
        ));
  }
}

class AddressExpansionTile extends StatelessWidget {
  final String addressId;
  final Map<String, dynamic> addressData;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AddressExpansionTile({
    super.key,
    required this.addressId,
    required this.addressData,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final street = addressData['street'] ?? '';
    final streetNumber = addressData['streetNumber'] ?? '';
    final city = addressData['city'] ?? '';
    final state = addressData['state'] ?? '';
    final zipCode = addressData['zipCode'] ?? '';

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: isDarkMode ? Colors.grey[800] : Colors.white,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          title: Text(
            '$street $streetNumber',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text('$city, $state, $zipCode'),
          children: [
            if (addressData['latitude'] != null &&
                addressData['longitude'] != null)
              SizedBox(
                height: 200,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      addressData['latitude'],
                      addressData['longitude'],
                    ),
                    zoom: 16,
                  ),
                  markers: {
                    Marker(
                      markerId: MarkerId(addressId),
                      position: LatLng(
                        addressData['latitude'],
                        addressData['longitude'],
                      ),
                    ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: false,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  liteModeEnabled: true,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'No hay ubicación disponible para esta dirección.',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onEdit,
                  child: const Text('Editar'),
                ),
                TextButton(
                  onPressed: onDelete,
                  child: const Text(
                    'Eliminar',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
