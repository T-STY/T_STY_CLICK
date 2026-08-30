# T_STY: Beyond — app de cliente (Flutter)

App de tienda y lealtad para T_STY. Bundle `com.tsty.mx.beyond`, proyecto
Firebase `arthemis-f2966`, compartido con el panel de administración
(`t_sty_delivery`), el punto de venta (`PDV_GEN2-main`) y el kiosco
(`kiosk_gen2`).

# Reglas

## Sin comentarios
No se escriben comentarios en el código, en ningún archivo bajo `lib/`. Ni
explicativos, ni de documentación (`///`), ni separadores de sección, ni TODOs.

La única excepción son los comentarios que la herramienta necesita para
funcionar: `// ignore:` y `// ignore_for_file:`.

La explicación va en el mensaje del commit, no en el archivo. Si un bloque
parece necesitar un comentario para entenderse, se renombra o se reestructura.

## Sin SnackBars
Nunca usar SnackBars. Usar AlertDialog o mensajes en línea.

## Color
Negro principalmente, gris a lo mucho. No introducir colores nuevos.

# Estructura

- `lib/app/home.dart` — shell del Home. Navegación por `IndexedStack`; las
  secciones internas (producto, combo, Apoyo) se abren dentro del shell para
  que la barra inferior no se mueva.
- `lib/app/home_blocks.dart` — bloques del home servidos desde Firestore
  (`home_sections`) y `dispatchHomeAction`, que resuelve la acción de un
  anuncio: `url`, `combo`, `category`, `brand`, `provedor`, `products`,
  `apoyo`.
- `lib/app/ads_carousel.dart` — carrusel de anuncios (`ads`).
- `lib/app/apoyo/` — Apoyo Social: alta, catálogo del ciclo, pedido y
  seguimiento.
- `lib/app/category/product_display.dart` — listado y ficha de producto.
- `lib/app/cart/` — carrito y monedero.
- `lib/app/game/` — Arcade Center, una función secundaria dentro de la app.
  Los juegos se dibujan con `CustomPainter`; no hay motor de juego.

# Datos

- Los productos guardan la imagen en `image_url`. Los anuncios, recetas y
  combos la guardan en `imageURL` / `imageUrl`.
- Los productos guardan el proveedor en `distribuitor_name` (con la errata).
