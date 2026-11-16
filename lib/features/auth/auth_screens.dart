import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/data/nova_store.dart';

String authErrorText(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Incorrect email or password';
    if (m.contains('already registered')) return 'An account with this email already exists';
    if (m.contains('database error')) return 'This phone number is already linked to an account';
    return e.message;
  }
  return 'Something went wrong. Check your connection and try again.';
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 28),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard,
    this.obscure = false,
    this.validator,
    this.suffix,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboard;
  final bool obscure;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        validator: validator,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixIcon: suffix),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final phoneFree = await sb.rpc('phone_available', params: {'_phone': _phone.text.trim()});
      if (phoneFree != true) {
        throw const AuthException('This phone number is already linked to an account');
      }
      await sb.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'full_name': _name.text.trim(), 'phone': _phone.text.trim()},
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Create your account',
      subtitle: 'Use your legal name as it appears on your BVN.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              _Field(
                controller: _name,
                label: 'Full legal name',
                icon: Icons.person_outline_rounded,
                validator: (v) =>
                    (v ?? '').trim().split(RegExp(r'\s+')).length < 2 ? 'Enter first and last name' : null,
              ),
              _Field(
                controller: _email,
                label: 'Email address',
                icon: Icons.mail_outline_rounded,
                keyboard: TextInputType.emailAddress,
                validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Enter a valid email',
              ),
              _Field(
                controller: _phone,
                label: 'Phone number',
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
                validator: (v) =>
                    RegExp(r'^(\+234|0)[789][01]\d{8}$').hasMatch((v ?? '').replaceAll(' ', ''))
                        ? null
                        : 'Enter a valid Nigerian number',
              ),
              _Field(
                controller: _password,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
                validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create Account'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context)
              .pushReplacement(MaterialPageRoute(builder: (_) => const SignInScreen())),
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await sb.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authErrorText(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter your email first')));
      return;
    }
    try {
      await sb.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password reset link sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authErrorText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to your NOVA account.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              _Field(
                controller: _email,
                label: 'Email address',
                icon: Icons.mail_outline_rounded,
                keyboard: TextInputType.emailAddress,
                validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
              ),
              _Field(
                controller: _password,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                obscure: _hide,
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign In'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context)
              .pushReplacement(MaterialPageRoute(builder: (_) => const SignUpScreen())),
          child: const Text("New to NOVA? Create an account"),
        ),
        const SizedBox(height: 20),
        Text(
            'Sandbox preview: no real money moves.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
      ],
    );
  }
}
