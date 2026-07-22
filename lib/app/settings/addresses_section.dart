import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

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
  // Delivery driver hint (entre calles, color de casa, portón…). Optional.
  final _referencesController = TextEditingController();

  final _city = 'Colima';
  final _state = 'Colima';
  LatLng? _selectedLocation;

  // "Usar mi ubicación" busy flag (GPS fix + reverse geocode).
  bool _prefillingFromGps = false;

  // In-card map step: when true, the add-address card swaps its form content
  // for the map picker (instead of popping a dialog).
  bool _showMap = false;
  LatLng? _mapInitial;
  bool _mapAutoLocate = false;

  String? _resolvedColonia() => _selectedColonia == kOtraColonia
      ? _customColoniaController.text.trim()
      : _selectedColonia;

  @override
  void dispose() {
    _streetController.dispose();
    _streetNumberController.dispose();
    _zipCodeController.dispose();
    _customColoniaController.dispose();
    _referencesController.dispose();
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
        if (_showMap) {
          setState(() => _showMap = false);
        } else if (_isAddingOrEditing) {
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
      _showMap = false;
      _populateFormFields(addressData);
    });
  }

  void _clearFormFields() {
    _streetController.clear();
    _streetNumberController.clear();
    _zipCodeController.clear();
    _selectedColonia = null;
    _customColoniaController.clear();
    _referencesController.clear();
    _selectedLocation = null;
    _showMap = false;
  }

  void _populateFormFields(Map<String, dynamic> addressData) {
    _streetController.text = addressData['street'] ?? '';
    _streetNumberController.text = addressData['streetNumber'] ?? '';
    _zipCodeController.text = addressData['zipCode'] ?? '';
    _referencesController.text = addressData['references'] ?? '';
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
          // Same card, two steps: the typed form, then — in place — the map
          // to confirm the exact pin.
          child: _showMap
              ? LocationPickerView(
                  key: const ValueKey('addr-map'),
                  initialLocation: _mapInitial ?? _kColimaFallback,
                  autoLocate: _mapAutoLocate,
                  onCancel: () => setState(() => _showMap = false),
                  onConfirm: (pos) {
                    setState(() => _showMap = false);
                    _saveAddress(pos);
                  },
                )
              : Column(
            children: [
              // Fastest path: drop the user at their GPS spot and prefill the
              // street fields from a reverse geocode. They can correct any
              // field after; the map step still confirms the exact pin.
              _buildUseMyLocationButton(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('o escríbela',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade300)),
                ],
              ),
              const SizedBox(height: 14),
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
                    _buildTextField(
                      _referencesController,
                      'Referencias (entre calles, color de casa…)',
                      required: false,
                    ),
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

  Widget _buildTextField(TextEditingController controller, String label,
      {bool required = true}) {
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
        if (!required) return null;
        if (value == null || value.isEmpty) {
          return 'Por favor, ingresa $label';
        }
        return null;
      },
    );
  }

  /// GPS + reverse-geocode prefill. Gets a precise fix, reverse-geocodes it,
  /// and drops the street/number/zip/colonia into the form (all editable
  /// after). Sets `_selectedLocation` so the map step opens on the real spot.
  Widget _buildUseMyLocationButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _prefillingFromGps ? null : _prefillFromGps,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: BorderSide(color: Colors.grey.shade400),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: _prefillingFromGps
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location, size: 18),
        label: Text(_prefillingFromGps
            ? 'Ubicando…'
            : 'Usar mi ubicación actual'),
      ),
    );
  }

  Future<void> _prefillFromGps() async {
    setState(() => _prefillingFromGps = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showAlertDialog('Ubicación desactivada',
            'Activa la ubicación de tu teléfono para usar esta opción.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showAlertDialog('Permiso necesario',
            'Necesitamos permiso de ubicación para llenar tu dirección.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _selectedLocation = LatLng(pos.latitude, pos.longitude);

      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final m = marks.first;
          if (!mounted) return;
          setState(() {
            if ((m.thoroughfare ?? '').isNotEmpty) {
              _streetController.text = m.thoroughfare!;
            }
            if ((m.subThoroughfare ?? '').isNotEmpty) {
              _streetNumberController.text = m.subThoroughfare!;
            }
            if ((m.postalCode ?? '').isNotEmpty) {
              _zipCodeController.text = m.postalCode!;
            }
            // subLocality ≈ colonia. Match it into the dropdown when the ZIP
            // knows it, else drop it into the free-text "Otra" field.
            final colonia = (m.subLocality ?? '').trim();
            if (colonia.isNotEmpty) {
              final items = coloniasForZip(_zipCodeController.text);
              if (items.contains(colonia)) {
                _selectedColonia = colonia;
              } else {
                _selectedColonia = kOtraColonia;
                _customColoniaController.text = colonia;
              }
            }
          });
        }
      } catch (_) {
        // Reverse geocode can fail (new colonia / offline) — the pin is still
        // set, so the map step works; the user just fills the fields.
      }
      // No confirmation dialog: the fields visibly populating is the feedback.
    } catch (e) {
      if (!mounted) return;
      _showAlertDialog('Error',
          'No pudimos obtener tu ubicación. Escribe la dirección manualmente.');
    } finally {
      if (mounted) setState(() => _prefillingFromGps = false);
    }
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

  // Colima centro — camera seed when the geocoder can't resolve the typed
  // address (brand-new colonias aren't in the geocoding database yet). The
  // typed address is saved verbatim either way; the geocode only positions
  // the initial map camera, so an unfound address must never be a dead end.
  static const LatLng _kColimaFallback = LatLng(19.2433, -103.7250);

  void _confirmAddress() async {
    if (_formKey.currentState!.validate()) {
      final colonia = _resolvedColonia();
      if (colonia == null || colonia.isEmpty) {
        _showAlertDialog('Error', 'Por favor, selecciona o escribe una colonia');
        return;
      }

      final addressString =
          '${_streetController.text} ${_streetNumberController.text}, $colonia, $_city, $_state, ${_zipCodeController.text}, México';

      LatLng? initialPosition;
      try {
        final locations = await locationFromAddress(addressString);
        if (locations.isNotEmpty) {
          initialPosition =
              LatLng(locations.first.latitude, locations.first.longitude);
        }
      } catch (_) {
        // Geocoder threw (new colonia, flaky service) — handled below; the
        // user can still continue and drop the pin themselves.
      }

      if (!mounted) return;

      // Unfound address: tell the user what we couldn't locate and let THEM
      // decide to continue — the map + GPS pin takes over from here.
      bool autoLocate = false;
      if (initialPosition == null) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('No encontramos esa dirección'),
            content: Text(
                'No pudimos ubicar en el mapa:\n\n"$addressString"\n\n'
                'Si es una colonia nueva es normal. ¿Quieres continuar y '
                'colocar la ubicación tú mismo en el mapa?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Revisar dirección'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continuar al mapa'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        autoLocate = true;
      }

      if (!mounted) return;
      // Swap the SAME card to the map step (no dialog).
      setState(() {
        _mapInitial =
            _selectedLocation ?? initialPosition ?? _kColimaFallback;
        _mapAutoLocate = autoLocate;
        _showMap = true;
      });
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
        'references': _referencesController.text.trim(),
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

/// Embeddable map picker — renders inline INSIDE the add-address card (no
/// dialog). Confirms the exact pin via [onConfirm]; [onCancel] returns to the
/// form. All the GPS-fix + "center on me" logic lives here.
class LocationPickerView extends StatefulWidget {
  final LatLng initialLocation;

  /// When true, pulls the client's GPS fix on open and drops the pin there
  /// without requiring a tap on the center button (which stays available).
  /// Used when the geocoder couldn't resolve the typed address.
  final bool autoLocate;

  final ValueChanged<LatLng> onConfirm;
  final VoidCallback onCancel;

  const LocationPickerView({
    super.key,
    required this.initialLocation,
    required this.onConfirm,
    required this.onCancel,
    this.autoLocate = false,
  });

  @override
  State<LocationPickerView> createState() => _LocationPickerViewState();
}

class _LocationPickerViewState extends State<LocationPickerView> {
  late LatLng _selectedPosition;
  GoogleMapController? _mapController;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _selectedPosition = widget.initialLocation;
    if (widget.autoLocate) {
      // After first frame so the map controller/permission dialogs have a
      // live context. _goToMyLocation already handles every failure mode
      // (service off, denied permission) with its own dialogs.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToMyLocation();
      });
    }
  }

  Future<void> _showInfo(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  /// Returns the most precise fix obtainable within a short window.
  ///
  /// A single `getCurrentPosition` often returns the FIRST fix the OS has —
  /// usually a coarse cell/Wi-Fi triangulation (~50m+) before the GPS chip
  /// settles. Instead we open a position STREAM at the highest accuracy and
  /// keep the reading with the smallest `accuracy` radius, finishing early
  /// once a tight (≤12m) GPS fix arrives, or after [budget] with the best
  /// reading seen. Falls back to a one-shot read if the stream yields nothing.
  Future<Position?> _getPreciseFix({
    Duration budget = const Duration(seconds: 6),
  }) async {
    Position? best;
    final completer = Completer<Position?>();
    StreamSubscription<Position>? sub;
    Timer? deadline;

    void finish() {
      if (completer.isCompleted) return;
      deadline?.cancel();
      sub?.cancel();
      completer.complete(best);
    }

    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      (p) {
        if (best == null || p.accuracy < best!.accuracy) best = p;
        // Good enough — a typical outdoor GPS lock is 3–10m.
        if (p.accuracy <= 12) finish();
      },
      onError: (_) => finish(),
    );

    deadline = Timer(budget, finish);

    final streamed = await completer.future;
    if (streamed != null) return streamed;

    // Stream gave nothing (e.g. emulator / no fix yet) — one-shot fallback.
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      return null;
    }
  }

  /// Drops the pin on the device's current GPS position. Requests precise
  /// location permission on demand; surfaces every failure mode through an
  /// AlertDialog (no SnackBars — project convention).
  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await _showInfo(
          'Ubicación desactivada',
          'Activa los servicios de ubicación de tu dispositivo para usar esta '
              'función.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        await _showInfo(
          'Permiso de ubicación',
          'Diste permiso de ubicación como denegado permanentemente. '
              'Actívalo desde la configuración del sistema para usar tu '
              'ubicación actual.',
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        await _showInfo(
          'Permiso de ubicación',
          'Necesitamos tu permiso de ubicación para colocar el pin en tu '
              'posición actual.',
        );
        return;
      }

      final pos = await _getPreciseFix();
      if (!mounted) return;
      if (pos == null) {
        await _showInfo(
          'No se pudo obtener tu ubicación',
          'Intenta de nuevo en un lugar con mejor señal o coloca el pin '
              'manualmente.',
        );
        return;
      }
      final here = LatLng(pos.latitude, pos.longitude);
      setState(() => _selectedPosition = here);
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(here, 18),
      );
    } catch (e) {
      await _showInfo(
        'No se pudo obtener tu ubicación',
        'Intenta de nuevo o coloca el pin manualmente.',
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            const Text(
              'Confirma la ubicación',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Arrastra el pin o toca el mapa para ajustar el punto exacto.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 340,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _selectedPosition,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  // Show the blue "you are here" dot once permission is
                  // granted; the custom button below is what actually moves
                  // the pin.
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
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
                    _mapController
                        ?.animateCamera(CameraUpdate.newLatLng(position));
                  },
                ),
                // "Use my location" button, above the native zoom controls.
                Positioned(
                  right: 8,
                  bottom: 100,
                  child: _MyLocationButton(
                    busy: _locating,
                    onTap: _goToMyLocation,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => widget.onConfirm(_selectedPosition),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirmar ubicación'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('Volver a la dirección'),
        ),
      ],
    );
  }
}

/// Circular "center on my location" control rendered over the map, styled to
/// sit naturally above Google's native zoom buttons.
class _MyLocationButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _MyLocationButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location, color: Colors.black87, size: 22),
        ),
      ),
    );
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
