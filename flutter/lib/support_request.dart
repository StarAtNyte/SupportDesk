import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_hbb/common.dart' hide Dialog;

enum _Step { form, submitting, success, error }

/// Dialog that lets an end-user submit a remote-support request directly
/// from inside the RustDesk / SupportClient app.
///
/// The caller is responsible for reading the support server URL from config
/// (via `bind.mainGetOptionSync(key: 'support-server-url')`) and passing it
/// in, together with the user's own RustDesk ID.
class SupportRequestDialog extends StatefulWidget {
  final String rustdeskId;
  final String supportServerUrl;

  const SupportRequestDialog({
    Key? key,
    required this.rustdeskId,
    required this.supportServerUrl,
  }) : super(key: key);

  @override
  State<SupportRequestDialog> createState() => _SupportRequestDialogState();
}

class _SupportRequestDialogState extends State<SupportRequestDialog> {
  final _nameCtrl    = TextEditingController();
  final _messageCtrl = TextEditingController();

  _Step  _step      = _Step.form;
  String _errorText = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  // ── submission ────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) {
      setState(() => _errorText = translate('Please describe your issue.'));
      return;
    }

    setState(() {
      _step      = _Step.submitting;
      _errorText = '';
    });

    try {
      final payload = <String, dynamic>{
        'rustdesk_id': widget.rustdeskId.replaceAll(' ', ''),
        'message': msg,
      };
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty) payload['name'] = name;

      final res = await http
          .post(
            Uri.parse('${widget.supportServerUrl}/api/support-request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 201) {
        setState(() => _step = _Step.success);
      } else {
        setState(() {
          _step      = _Step.error;
          _errorText = 'Server returned ${res.statusCode}. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _step      = _Step.error;
        _errorText =
            translate('Connection failed. Check your internet and try again.');
      });
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.success:
        return _buildSuccess();
      case _Step.error:
        return _buildError();
      default:
        return _buildForm();
    }
  }

  // ── form step ─────────────────────────────────────────────────────────────

  Widget _buildForm() {
    final submitting = _step == _Step.submitting;

    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── header ──────────────────────────────────────────────────────────
        Row(
          children: [
            Icon(Icons.support_agent_rounded,
                color: MyTheme.accent, size: 24),
            const SizedBox(width: 10),
            Text(
              translate('Request Support'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          translate(
              'Our team will connect to your computer remotely. Please keep this app open after sending.'),
          style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 24),

        // ── your ID (read-only) ──────────────────────────────────────────────
        _fieldLabel(translate('Your Support ID')),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white10
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white24
                  : const Color(0xFFCBD5E1),
            ),
          ),
          child: SelectableText(
            widget.rustdeskId.isEmpty
                ? translate('Generating...')
                : widget.rustdeskId,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: MyTheme.accent,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 18),

        // ── name (optional) ─────────────────────────────────────────────────
        _fieldLabel('${translate('Your Name')} (${translate('optional')})'),
        const SizedBox(height: 6),
        TextField(
          controller: _nameCtrl,
          enabled: !submitting,
          textInputAction: TextInputAction.next,
          decoration: _inputDeco(translate('e.g. John Smith')),
        ),
        const SizedBox(height: 16),

        // ── issue description (required) ─────────────────────────────────────
        _fieldLabel(translate('Describe your issue')),
        const SizedBox(height: 6),
        TextField(
          controller: _messageCtrl,
          enabled: !submitting,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: _inputDeco(translate('What do you need help with?')),
        ),

        // ── validation error ─────────────────────────────────────────────────
        if (_errorText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 15, color: Colors.redAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _errorText,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 26),

        // ── action buttons ───────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    submitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(translate('Cancel')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  disabledBackgroundColor: MyTheme.accent.withValues(alpha: 0.6),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Text(
                        translate('Send Request'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── success step ──────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_rounded,
            color: Colors.green, size: 60),
        const SizedBox(height: 18),
        Text(
          translate('Request Sent!'),
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          translate(
              'Our support team has been notified and will connect to your computer shortly. Please keep this app open and accept the incoming connection.'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey[600], height: 1.6),
        ),
        const SizedBox(height: 8),
        // remind them of their ID
        Text(
          '${translate("Your ID")}: ${widget.rustdeskId}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: MyTheme.accent,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              translate('Close'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // ── error step ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Column(
      key: const ValueKey('error'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.orange, size: 60),
        const SizedBox(height: 18),
        Text(
          translate('Something went wrong'),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          _errorText,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, color: Colors.grey[600], height: 1.5),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(translate('Cancel')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _step      = _Step.form;
                  _errorText = '';
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  translate('Try Again'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      );
}
