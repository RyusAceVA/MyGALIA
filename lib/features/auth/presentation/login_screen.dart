import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mygalia/core/constants/app_constants.dart';
import 'package:mygalia/core/network/failure.dart';
import 'package:mygalia/core/presentation/expressive/loading_indicator.dart';
import 'package:mygalia/core/presentation/expressive/material_shapes.dart';
import 'package:mygalia/core/presentation/expressive/shape_badge.dart';
import 'package:mygalia/features/auth/presentation/auth_controller.dart';

/// Écran de connexion avec le compte SC Form.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.message});

  /// Raison du retour à cet écran (ex. identifiants refusés).
  final String? message;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final Failure? failure = await ref
        .read(authControllerProvider.notifier)
        .signIn(_email.text, _password.text);
    if (!mounted) return;
    if (failure == null) {
      TextInput.finishAutofillContext();
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? notice = widget.message;
    final String? error = _error;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: ShapeBadge(
                          shape: MaterialShapes.cookie9,
                          initialShape: MaterialShapes.circle,
                          size: 88,
                          color: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.school_rounded,
                            size: 40,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        AppConstants.appName,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Connectez-vous avec votre compte SC Form.',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      if (notice != null) ...[
                        Card(
                          color: theme.colorScheme.errorContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              notice,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        enabled: !_submitting,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email, AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Saisissez votre adresse e-mail.'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        enabled: !_submitting,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Afficher' : 'Masquer',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (String? value) => (value == null || value.isEmpty)
                            ? 'Saisissez votre mot de passe.'
                            : null,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Text(error, style: TextStyle(color: theme.colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const ExpressiveLoadingIndicator(
                                size: 32,
                                semanticsLabel: 'Connexion en cours',
                              )
                            : const Text('Se connecter'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Vos identifiants restent chiffrés sur cet appareil et '
                        'servent uniquement à vous reconnecter automatiquement.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
