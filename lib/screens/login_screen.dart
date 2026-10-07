import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_config.dart';
import '../services/api_service.dart';
import '../services/biometric_service.dart';
import 'doctor_masterlist_screen.dart';
import 'list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _isBiometricAvailable = false;
  bool _hasSavedCredentials = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final available = await BiometricService.isBiometricAvailable();
    final credentials = await BiometricService.getSavedCredentials();
    if (mounted) {
      setState(() {
        _isBiometricAvailable = available;
        _hasSavedCredentials = credentials != null;
        if (credentials != null && credentials['username'] != null) {
          _usernameController.text = credentials['username']!;
        }
      });
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final apiService = Provider.of<ApiService>(context, listen: false);
    final success = await apiService.login(username, password);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        await BiometricService.saveCredentials(username, password);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppConfig.mode == AppMode.corenergy
                ? const ListScreen()
                : const DoctorMasterlistScreen(),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Authentication failed. Please verify your credentials.';
        });
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    final credentials = await BiometricService.getSavedCredentials();
    if (credentials == null) {
      setState(() {
        _errorMessage = 'No saved credentials found. Please log in manually first.';
      });
      return;
    }

    final authenticated = await BiometricService.authenticate();
    if (!authenticated) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = credentials['username']!;
    final password = credentials['password']!;

    final apiService = Provider.of<ApiService>(context, listen: false);
    final success = await apiService.login(username, password);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AppConfig.mode == AppMode.corenergy
                ? const ListScreen()
                : const DoctorMasterlistScreen(),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Biometric login failed. Please verify your credentials manually.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Image
          Image.asset(
            'assets/medical_bg.jpg',
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
          // Soft blue theme overlay
          Container(
            color: const Color(0xFF0056B3).withOpacity(0.15),
          ),
          // Blur Filter
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
            child: Container(
              color: Colors.black.withOpacity(0.1),
            ),
          ),
          // Login Form
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 25,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo Container
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0056B3), Color(0xFF007AFF)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0056B3).withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.donut_large,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // App Title
                        Text(
                          AppConfig.mode == AppMode.corenergy ? 'PIMS MCP' : 'PIMS HCP',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF0056B3),
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 36),
                        
                        // Username Field
                        const Text(
                          'USERNAME',
                          style: TextStyle(
                            color: Color(0xFF56565A),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _usernameController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Color(0xFF1C1C1E)),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF8E8E93)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF0056B3), width: 2),
                            ),
                            hintText: 'name@company.com',
                            hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your username';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        
                        // Password Field
                        const Text(
                          'PASSWORD',
                          style: TextStyle(
                            color: Color(0xFF56565A),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Color(0xFF1C1C1E)),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF8E8E93)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: const Color(0xFF8E8E93),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF0056B3), width: 2),
                            ),
                            hintText: 'Enter password',
                            hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 30),
                        
                        if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Login Button
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0056B3),
                            disabledBackgroundColor: const Color(0xFF0056B3).withOpacity(0.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        if (_isBiometricAvailable && _hasSavedCredentials) ...[
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _isLoading ? null : _handleBiometricLogin,
                            icon: const Icon(Icons.fingerprint, size: 22, color: Color(0xFF0056B3)),
                            label: const Text(
                              'Biometric Login',
                              style: TextStyle(
                                color: Color(0xFF0056B3),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFF0056B3), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
