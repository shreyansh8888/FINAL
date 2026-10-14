import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/services/firebase_service.dart';
import '../../../navigation/app_router.dart';
import '../widgets/gradient_header.dart';

/// Phone OTP authentication screen.
///
/// Uses [FirebaseService] which is currently a no-op stub.
/// When you configure Firebase, replace the stub methods in
/// lib/core/services/firebase_service.dart — this screen needs no changes.
class PhoneOtpScreen extends ConsumerStatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  ConsumerState<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends ConsumerState<PhoneOtpScreen> {
  final _phoneCtrl = TextEditingController();
  String _otp = '';
  bool _otpSent = false;
  bool _loading = false;
  String? _errorMessage;

  final _firebase = FirebaseService.instance;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.length < 10) {
      _setError('Enter a valid 10-digit phone number');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    // E.164 format — prepend +91 if the user omits the country code
    final e164 = raw.startsWith('+') ? raw : '+91$raw';
    final result = await _firebase.sendOtp(e164);

    if (!mounted) return;

    switch (result) {
      case OtpSendResult.success:
        setState(() {
          _otpSent = true;
          _loading = false;
        });
      case OtpSendResult.invalidPhone:
        setState(() {
          _loading = false;
          _errorMessage = 'Invalid phone number. Check and try again.';
        });
      case OtpSendResult.tooManyRequests:
        setState(() {
          _loading = false;
          _errorMessage = 'Too many attempts. Please try after some time.';
        });
      case OtpSendResult.unknown:
        setState(() {
          _loading = false;
          _errorMessage = 'Could not send OTP. Please try again.';
        });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.length != 6) {
      _setError('Enter the full 6-digit OTP');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final result = await _firebase.verifyOtp(_otp);

    if (!mounted) return;

    switch (result) {
      case OtpVerifyResult.success:
        context.go(AppRoutes.home);
      case OtpVerifyResult.wrongCode:
        setState(() {
          _loading = false;
          _errorMessage = 'Incorrect OTP. Please try again.';
        });
      case OtpVerifyResult.expired:
        setState(() {
          _loading = false;
          _errorMessage = 'OTP expired. Go back and request a new one.';
        });
      case OtpVerifyResult.unknown:
        setState(() {
          _loading = false;
          _errorMessage = 'Verification failed. Please try again.';
        });
    }
  }

  void _setError(String msg) =>
      setState(() => _errorMessage = msg);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SingleChildScrollView(
        child: Column(
          children: [
            const GradientHeader(
              title: 'Phone Login',
              subtitle: 'Verify with OTP',
              showBack: true,
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (!_otpSent) ...[
                    const Text(
                      'Enter your mobile number to receive a one-time password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, height: 1.6),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        prefixText: '+91 ',
                        prefixIcon: Icon(Icons.phone),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _sendOtp,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Send OTP'),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Enter the 6-digit code sent to\n+91 ${_phoneCtrl.text.trim()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, height: 1.6),
                    ),
                    const SizedBox(height: 32),
                    PinCodeTextField(
                      appContext: context,
                      length: 6,
                      animationType: AnimationType.fade,
                      keyboardType: TextInputType.number,
                      pinTheme: PinTheme(
                        shape: PinCodeFieldShape.box,
                        borderRadius: BorderRadius.circular(8),
                        fieldHeight: 50,
                        fieldWidth: 44,
                        activeFillColor: Colors.white,
                        activeColor: AppColors.primary,
                        selectedColor: AppColors.primaryDark,
                        inactiveColor: Colors.grey.shade300,
                      ),
                      onChanged: (v) => _otp = v,
                      onCompleted: (_) => _verifyOtp(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _verifyOtp,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Verify OTP'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _otpSent = false;
                        _otp = '';
                        _errorMessage = null;
                      }),
                      child: const Text('Change Number'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
