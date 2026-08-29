import 'dart:convert';

import 'package:click/app/apoyo/apoyo_cart_provider.dart';
import 'package:click/app/apoyo/apoyo_cycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

ApoyoCatalogItem _item(String id, double price, {String unidad = 'pz'}) =>
    ApoyoCatalogItem(
      id: id,
      nombre: id,
      unidad: unidad,
      imageUrl: '',
      memberPrice: price,
      maxPerMember: 0,
      cycleCap: 0,
      orden: 0,
      components: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('money — must match placeApoyoOrder exactly', () {
    test('rounds like Math.round(x * 100) / 100', () {
      expect(apoyoRound2(37.5 * 0.5), 18.75);
      expect(apoyoRound2(0.1 + 0.2), 0.3);
      expect(apoyoRound2(19.999), 20.0);
      expect(apoyoRound2(2.345), 2.35); // half rounds up, as in JS
    });

    test('subtotal rounds each line, then the sum', () {
      final lines = [
        ApoyoDraftLine(_item('a', 33.33), 3),
        ApoyoDraftLine(_item('b', 24.5, unidad: 'kg'), 1.5),
        ApoyoDraftLine(_item('c', 9.99), 2),
      ];
      expect(lines[0].total, 99.99);
      expect(lines[1].total, 36.75);
      expect(lines[2].total, 19.98);
      expect(apoyoDraftSubtotal(lines), 156.72);
    });
  });

  group('formatting — never derived from the cycle id', () {
    test('the delivery Friday comes out as the Friday', () async {
      await initializeDateFormatting('es', null);
      // Local midday on the delivery Friday, as a Timestamp would arrive.
      final friday = DateTime(2026, 9, 4, 15);
      expect(apoyoLongDate(friday), 'viernes 4 de septiembre');
      expect(apoyoClock(friday), '3:00 PM');
      expect(apoyoClock(DateTime(2026, 9, 4, 23, 59, 59)), '11:59 PM');
      expect(apoyoClock(DateTime(2026, 9, 4, 0, 5)), '12:05 AM');
    });

    test('quantities keep half kilos', () {
      expect(apoyoQty(2), '2');
      expect(apoyoQty(1.5), '1.5');
      expect(apoyoQtyUnit(1.5, 'kg'), '1.5 kg');
      expect(apoyoQtyUnit(3, 'pz'), '3 pz');
    });

    test('countdown copy', () {
      expect(apoyoCountdown(const Duration(days: 2, hours: 5)), '2 días 5 h');
      expect(apoyoCountdown(const Duration(hours: 1, minutes: 2)), '1 h 2 min');
      expect(apoyoCountdown(const Duration(seconds: 42)), '42 s');
      expect(apoyoCountdown(Duration.zero), 'Cerrado');
      expect(apoyoCountdown(const Duration(seconds: -5)), 'Cerrado');
    });
  });

  group('cycle openness follows the stored instant', () {
    final closes = DateTime(2026, 9, 1, 23, 59, 59);
    final cycle = ApoyoCycle(
      id: '2026-09-04',
      state: 'abierto',
      closesAt: closes,
      deliveryAt: DateTime(2026, 9, 4, 15),
    );

    test('open before the cutoff, closed after it', () {
      expect(cycle.isOpenAt(closes.subtract(const Duration(seconds: 1))), true);
      expect(cycle.isOpenAt(closes.add(const Duration(seconds: 1))), false);
    });

    test('a cerrado cycle is closed even before its cutoff', () {
      final closed = ApoyoCycle(
        id: '2026-09-04',
        state: 'cerrado',
        closesAt: closes,
      );
      expect(closed.isOpenAt(closes.subtract(const Duration(days: 1))), false);
    });
  });

  group('ApoyoCartProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('persists only ids and quantities', () async {
      final cart = ApoyoCartProvider();
      await cart.ready;
      cart.setQty(
          cycleId: '2026-09-04', catalogItemId: 'arroz', quantity: 2);
      cart.setQty(
          cycleId: '2026-09-04', catalogItemId: 'aceite', quantity: 1.5);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(ApoyoCartProvider.storageKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['cycleId'], '2026-09-04');
      expect(decoded['lines'], [
        {'catalogItemId': 'arroz', 'quantity': 2},
        {'catalogItemId': 'aceite', 'quantity': 1.5},
      ]);
      // No price, no name, no snapshot copy.
      expect(raw.contains('price'), false);
      expect(raw.contains('nombre'), false);
    });

    test('a selection from another cycle survives until it is resolved',
        () async {
      SharedPreferences.setMockInitialValues({
        ApoyoCartProvider.storageKey: jsonEncode({
          'cycleId': '2026-08-28',
          'lines': [
            {'catalogItemId': 'arroz', 'quantity': 2},
          ],
        }),
      });
      final cart = ApoyoCartProvider();
      await cart.ready;
      expect(cart.cycleId, '2026-08-28');
      expect(cart.qtyOf('arroz'), 2);

      cart.adoptCycle('2026-09-04');
      expect(cart.cycleId, '2026-09-04');
      expect(cart.qtyOf('arroz'), 2, reason: 'moving weeks keeps the lines');

      cart.startFresh('2026-09-04');
      expect(cart.isEmpty, true);
    });

    test('a stored selection with no cycle is unusable and dropped', () async {
      SharedPreferences.setMockInitialValues({
        ApoyoCartProvider.storageKey: jsonEncode({
          'lines': [
            {'catalogItemId': 'arroz', 'quantity': 2},
          ],
        }),
      });
      final cart = ApoyoCartProvider();
      await cart.ready;
      expect(cart.isEmpty, true);
    });

    test('pruneTo drops entries that left the snapshot', () async {
      final cart = ApoyoCartProvider();
      await cart.ready;
      cart.setQty(cycleId: 'c', catalogItemId: 'arroz', quantity: 1);
      cart.setQty(cycleId: 'c', catalogItemId: 'viejo', quantity: 1);
      expect(cart.pruneTo({'arroz'}), ['viejo']);
      expect(cart.lineCount, 1);
      expect(cart.pruneTo({'arroz'}), isEmpty);
    });

    test('replaceAll seeds an edit from the placed order', () async {
      final cart = ApoyoCartProvider();
      await cart.ready;
      cart.replaceAll('2026-09-04', {'arroz': 2, 'nada': 0});
      expect(cart.lineCount, 1);
      expect(cart.qtyOf('arroz'), 2);
    });

    test('clear wipes the stored key', () async {
      final cart = ApoyoCartProvider();
      await cart.ready;
      cart.setQty(cycleId: 'c', catalogItemId: 'arroz', quantity: 1);
      await Future<void>.delayed(Duration.zero);
      cart.clear();
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ApoyoCartProvider.storageKey), isNull);
      expect(cart.isEmpty, true);
    });
  });
}
