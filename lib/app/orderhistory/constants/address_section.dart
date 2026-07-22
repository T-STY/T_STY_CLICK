import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AddressDisplayTile extends StatelessWidget {
  final String addressId;
  final Map<String, dynamic> addressData;

  const AddressDisplayTile({
    super.key,
    required this.addressId,
    required this.addressData,
  });

  @override
  Widget build(BuildContext context) {
    final street = addressData['street'] ?? '';
    final streetNumber = addressData['streetNumber'] ?? '';
    final city = addressData['city'] ?? '';
    final state = addressData['state'] ?? '';
    final zipCode = addressData['zipCode'] ?? '';
    final references = (addressData['references'] ?? '').toString().trim();

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
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
          subtitle: Text(references.isEmpty
              ? '$city, $state, $zipCode'
              : '$city, $state, $zipCode\nRef: $references'),
          children: [
            if (addressData['latitude'] != null && addressData['longitude'] != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                child: SizedBox(
                  height: 180,
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
          ],
        ),
      ),
    );
  }
}
