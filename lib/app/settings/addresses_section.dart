import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

import '../../components/shimmer_placeholder.dart';
import '../../constants/app_images.dart';

class AddressesSection extends StatefulWidget {
  final VoidCallback onBack;
  const AddressesSection({Key? key, required this.onBack}) : super(key: key);

  @override
  _AddressesSectionState createState() => _AddressesSectionState();
}

class _AddressesSectionState extends State<AddressesSection> {
  final _formKey = GlobalKey<FormState>();

  // Variables for managing form visibility and data
  bool _isAddingOrEditing = false;
  String? _editingAddressId;
  Map<String, dynamic>? _editingAddressData;

  // Form controllers
  final _streetController = TextEditingController();
  final _streetNumberController = TextEditingController();
  String? _selectedColonia;
  final _zipCodeController = TextEditingController();

  // Other variables
  final _colonias = ['Andares del Jazmin', 'Rivera del Jazmin'];
  final _city = 'Colima';
  final _state = 'Colima';
  LatLng? _selectedLocation;

  @override
  void dispose() {
    _streetController.dispose();
    _streetNumberController.dispose();
    _zipCodeController.dispose();
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

    return WillPopScope(
      onWillPop: () async {
        if (_isAddingOrEditing) {
          setState(() {
            _isAddingOrEditing = false;
          });
          return false;
        } else {
          widget.onBack();
          return false;
        }
      },
      child: StreamBuilder<QuerySnapshot>(
        stream: addressesRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // NEW: Shimmer List for Addresses
            return Scaffold(
              appBar: AppBar(
                backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
                elevation: 0,
              ),
              body: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: 3, // Show 3 dummy address cards
                itemBuilder: (context, index) {
                  return Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          // Street Name Placeholder
                          ShimmerPlaceholder(width: 200, height: 16),
                          SizedBox(height: 8),
                          // City/State Placeholder
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
            // Handle any errors in fetching data
            return Scaffold(
              appBar: AppBar(
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

          int addressCount = snapshot.data?.docs.length ?? 0;

          return Scaffold(
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
              backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
              elevation: 0,
              centerTitle: true,
              leading: SizedBox(),
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
                    icon: const Icon(Icons.add_location_alt, color: Colors.black),
                    onPressed: _startAddingAddress,
                  ),
                ),
              ]
                  : [
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    icon:
                    const Icon(Icons.add_location_alt, color: Colors.transparent),
                    onPressed: () {},
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
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final addressDoc = snapshot.data!.docs[index];
                final address = addressDoc.data() as Map<String, dynamic>;
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
          );
        },
      ),
    );
  }

  void _startAddingAddress() {
    setState(() {
      _isAddingOrEditing = true;
      _editingAddressId = null;
      _editingAddressData = null;
      _clearFormFields();
    });
  }

  void _startEditingAddress(String addressId, Map<String, dynamic> addressData) {
    setState(() {
      _isAddingOrEditing = true;
      _editingAddressId = addressId;
      _editingAddressData = addressData;
      _populateFormFields(addressData);
    });
  }

  void _clearFormFields() {
    _streetController.clear();
    _streetNumberController.clear();
    _selectedColonia = null;
    _zipCodeController.clear();
    _selectedLocation = null;
  }

  void _populateFormFields(Map<String, dynamic> addressData) {
    _streetController.text = addressData['street'] ?? '';
    _streetNumberController.text = addressData['streetNumber'] ?? '';
    _selectedColonia = addressData['colonia'];
    _zipCodeController.text = addressData['zipCode'] ?? '';
    if (addressData['latitude'] != null && addressData['longitude'] != null) {
      _selectedLocation = LatLng(
        addressData['latitude'],
        addressData['longitude'],
      );
    }
  }

  Widget _buildAddressForm() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isEditing = _editingAddressId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
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
                    // Wrap the dropdown field with StatefulBuilder
                    StatefulBuilder(
                      builder: (BuildContext context, StateSetter setState) {
                        return _buildDropdownField(
                          value: _selectedColonia,
                          label: 'Colonia',
                          items: _colonias,
                          onChanged: (value) {
                            setState(() {
                              _selectedColonia = value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildDisabledField('Ciudad', _city),
                    const SizedBox(height: 10),
                    _buildDisabledField('Estado', _state),
                    const SizedBox(height: 10),
                    _buildTextField(_zipCodeController, 'Código Postal'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _confirmAddress,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black,
                  // Text color
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

  Widget _buildDropdownField({
    required String? value,
    required String label,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonFormField<String>(
      value: value,
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
          return 'Por favor, selecciona $label';
        }
        return null;
      },
    );
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

  void _confirmAddress() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedColonia == null) {
        _showAlertDialog('Error', 'Por favor, selecciona una colonia');
        return;
      }

      // Build the full address string
      final addressString =
          '${_streetController.text} ${_streetNumberController.text}, $_selectedColonia, $_city, $_state, ${_zipCodeController.text}, México';

      try {
        // Use geocoding to get latitude and longitude
        List<Location> locations = await locationFromAddress(addressString);
        if (locations.isNotEmpty) {
          final location = locations.first;
          LatLng initialPosition = LatLng(location.latitude, location.longitude);

          // Show a dialog for user to confirm location
          LatLng? selectedPosition = await showDialog<LatLng>(
            context: context,
            builder: (context) => ConfirmLocationDialog(
              initialLocation: _selectedLocation ?? initialPosition,
            ),
          );

          if (selectedPosition != null) {
            // Save address data along with coordinates
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
      _showAlertDialog('Error', 'Por favor, corrige los errores en el formulario');
    }
  }

  void _saveAddress(LatLng position) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      final addressesRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('addresses');

      // Check if the user already has 3 addresses
      final querySnapshot = await addressesRef.get();
      if (querySnapshot.docs.length >= 3 && _editingAddressId == null) {
        // User already has 3 addresses and is trying to add a new one
        _showAlertDialog('Información', 'No puedes agregar más de 3 direcciones');
        return;
      }

      final data = {
        'street': _streetController.text,
        'streetNumber': _streetNumberController.text,
        'colonia': _selectedColonia,
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
                    Navigator.of(context).pop(); // Cancel
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
                      Navigator.of(context).pop(); // Confirm
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

  const ConfirmLocationDialog({Key? key, required this.initialLocation})
      : super(key: key);

  @override
  _ConfirmLocationDialogState createState() => _ConfirmLocationDialogState();
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
                Navigator.of(context).pop(null); // Cancel
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
    Key? key,
    required this.addressId,
    required this.addressData,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

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
                  liteModeEnabled: true, // Use lite mode for better performance
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
            ButtonBar(
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
