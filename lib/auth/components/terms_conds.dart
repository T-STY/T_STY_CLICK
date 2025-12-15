import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

class TermsAndConditionsScreen extends StatelessWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Blur effect layer
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // Actual AlertDialog without any blur
        Center(
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25.0),
            ),
            content: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Términos y Condiciones',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20.0),
                    RichText(
                      textAlign: TextAlign.justify,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.normal,
                          color: Theme.of(context).textTheme.bodyLarge?.color, // Adapt color based on theme
                        ),
                        children: <TextSpan>[
                          const TextSpan(
                            text: 'Condiciones generales de T_STY\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Introducción:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Gracias por elegir T_STY. Al acceder, utilizar o registrarse en cualquiera de los servicios prestados por T_STY, ya sea a través de nuestro sitio web o de la aplicación móvil, usted acepta los términos que se describen a continuación. Por favor, revíselas detenidamente.\n\n',
                          ),
                          const TextSpan(
                            text: 'Disposiciones Generales:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Este documento rige los términos bajo los cuales usted puede acceder y utilizar nuestros servicios. Estos términos son vinculantes y exigibles a toda persona que acceda o utilice nuestros servicios.\n\n',
                          ),
                          const TextSpan(
                            text: 'Uso de los servicios de Arthemis:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Los usuarios deben proporcionar información precisa y actualizada al registrarse en nuestros servicios. Cualquier información falsa puede dar lugar a la suspensión o cancelación de su cuenta Arthemis. El usuario es el único responsable de mantener la confidencialidad de sus credenciales de acceso.\n\n',
                          ),
                          const TextSpan(
                            text: 'Productos y servicios:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Nos esforzamos por garantizar que las descripciones, imágenes y precios de los productos y servicios sean precisos. Sin embargo, pueden producirse errores y nos reservamos el derecho a corregirlos. Los precios listados en T_STY incluyen cualquier impuesto aplicable según lo requerido por la ley mexicana.\n\n',
                          ),
                          const TextSpan(
                            text: 'Pedidos, pagos y entrega:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: '-Todos los pedidos realizados a través de T_STY están sujetos a la disponibilidad del producto y a la aceptación de nuestro equipo.\n\n-Aceptamos las principales tarjetas de crédito/débito y otros métodos de pago aprobados. El importe cobrado será en Pesos Mexicanos (MXN).\n\n-Las entregas se realizarán en la dirección que indique al realizar el pedido. Nuestro objetivo es realizar la entrega en el plazo indicado, pero factores ajenos a nuestra voluntad podrían afectar a los plazos de entrega.\n\n',
                          ),
                          const TextSpan(
                            text: 'Devoluciones y cancelaciones:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: '-Las compras realizadas a través de T_STY pueden devolverse de acuerdo con nuestra política de devoluciones.\n\n-Los pedidos pueden cancelarse antes de su envío. Para cancelaciones posteriores al envío, consulte nuestra política de devoluciones.\n\n',
                          ),
                          const TextSpan(
                            text: 'Propiedad intelectual:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: '- El software, el diseño de la aplicación, el logotipo de T_STY y los gráficos generales no asociados a productos específicos son propiedad de T_STY.\n\n'
                                '- Los productos, logotipos de marcas y materiales gráficos asociados a los mismos son propiedad de sus respectivas compañías y titulares.\n\n'
                                '- Todo el contenido está protegido por las leyes internacionales de propiedad intelectual. El uso no autorizado de cualquier material sin el consentimiento expreso por escrito de su respectivo propietario está estrictamente prohibido.\n\n',
                          ),
                          const TextSpan(
                            text: 'Limitación de responsabilidad y garantía:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: '-T_STY proporciona sus servicios "tal cual" y "según disponibilidad", sin garantías de ningún tipo, ni expresas ni implícitas.\n\n-En la medida en que lo permita la ley, T_STY no será responsable de ninguna pérdida o daño directo, indirecto o consecuente derivado del uso o de la imposibilidad de usar nuestros servicios.\n\n',
                          ),
                          const TextSpan(
                            text: 'Cambios en las Condiciones:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'T_STY se reserva el derecho de cambiar, modificar o revisar estos términos en cualquier momento. Cualquier cambio será efectivo inmediatamente después de su publicación en nuestras plataformas.\n\n',
                          ),
                          const TextSpan(
                            text: 'Legislación aplicable:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Estos términos se rigen e interpretan de acuerdo con las leyes de México. Cualquier disputa que surja de o en relación con estos términos estará sujeta a la jurisdicción de los tribunales de México.\n\n',
                          ),
                          const TextSpan(
                            text: 'Privacidad y protección de datos:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Estamos comprometidos a proteger la privacidad y seguridad de nuestros usuarios. Nuestra Política de Privacidad, que describe nuestras prácticas y políticas relacionadas con la recopilación, uso y almacenamiento de la información de nuestros usuarios, se incorpora a estos términos.\n\n',
                          ),
                          const TextSpan(
                            text: 'Información de contacto:\n\n',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(
                            text: 'Para cualquier consulta, duda o notificación, puede ponerse en contacto con nosotros en soporte@t-sty.mx',
                          ),
                        ],
                      ),
                    )
                  ],
                ),

              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(vertical: 20),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.5,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.0),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                    elevation: 2,
                  ),
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.normal,
                      color: AppColors.defaultWhite,
                      letterSpacing: 1.0,
                      fontFamily: 'Gordita',
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}

