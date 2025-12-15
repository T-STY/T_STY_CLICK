import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

// Define a Bloc for managing the Algolia products state
class AlgoliaProductsBloc extends Cubit<List<Map<String, dynamic>>> {
  AlgoliaProductsBloc() : super([]);

  // Method to fetch products based on the filter
  void fetchProducts(String filter) {
    // Perform Algolia API call and update state with the fetched products
    // Replace this with your actual Algolia API call
    List<Map<String, dynamic>> products = [
      {"imageURL": "url1", "title": "Product 1", "price": 10.0, "sizes": ["S", "M", "L"]},
      {"imageURL": "url2", "title": "Product 2", "price": 20.0, "sizes": ["M", "L", "XL"]},
      {"imageURL": "url3", "title": "Product 3", "price": 30.0, "sizes": ["L", "XL", "XXL"]},
    ];
    emit(products);
  }
}

class AlgoliaProductsGrid extends StatelessWidget {
  final String filter;

  const AlgoliaProductsGrid({super.key, required this.filter});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AlgoliaProductsBloc(),
      child: BlocBuilder<AlgoliaProductsBloc, List<Map<String, dynamic>>>(
        builder: (context, products) {
          // Fetch products when the widget is built
          context.read<AlgoliaProductsBloc>().fetchProducts(filter);

          return MasonryGridView.builder(
            gridDelegate: const SliverSimpleGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.network(product["imageURL"] ?? ""),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product["title"] ?? ""),
                          Text("\$${product["price"] ?? ""}"),
                          Wrap(
                            spacing: 8.0,
                            children: (product["sizes"] as List<String>? ?? []).map((size) {
                              return Chip(label: Text(size));
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
