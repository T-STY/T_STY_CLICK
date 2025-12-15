import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MultiFactorSignInScreen extends StatefulWidget {
  final String email;
  final String password;

  const MultiFactorSignInScreen({super.key, required this.email, required this.password});

  @override
  _MultiFactorSignInScreenState createState() => _MultiFactorSignInScreenState();
}

class _MultiFactorSignInScreenState extends State<MultiFactorSignInScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _verificationCodeController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      _promptForPhoneNumber();
    });
  }

  void _promptForPhoneNumber() {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Enter Phone Number'),
            content: Row(
              children: [
                const Text('+52'),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phoneNumberController,
                    decoration: const InputDecoration(
                        labelText: "Phone Number",
                        border: OutlineInputBorder()
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _registerWithEmailAndPassword('+52${_phoneNumberController.text}');
                },
                child: const Text("Submit"),
              )
            ],
          );
        }
    );
  }

  void _registerWithEmailAndPassword(String phoneNumber) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
          email: widget.email, password: widget.password);

      if (userCredential.user != null) {
        _verifyPhoneNumber(phoneNumber);
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.code}')));
    }
  }

  void _verifyPhoneNumber(String phoneNumber) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.currentUser?.linkWithCredential(credential);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created and phone number linked!'))
        );
      },
      verificationFailed: (FirebaseAuthException e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.code}')));
      },
      codeSent: (String verificationId, int? resendToken) {
        showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                content: TextField(
                  controller: _verificationCodeController,
                  decoration: const InputDecoration(labelText: "Enter SMS Code"),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      PhoneAuthCredential credential = PhoneAuthProvider.credential(
                          verificationId: verificationId,
                          smsCode: _verificationCodeController.text);
                      await _auth.currentUser?.linkWithCredential(credential);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Phone number linked!'))
                      );
                      Navigator.of(context).pop(); // Close the dialog
                    },
                    child: const Text("Verify"),
                  )
                ],
              );
            }
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Verify Multi-Factor Authentication"),
      ),
      body: const Center(
        child: Text("Please enter your phone number for verification"),
      ),
    );
  }
}

