import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String kPrivacyPolicyUrl =
    'https://docs.google.com/document/d/1tX5QrGESnrV6fKy8uTBY4zHlV82vUA12BDc-lSlmozk/edit?usp=sharing';

const String kMedicalDisclaimer =
    'CogniCare is not a medical device and does not diagnose, treat, cure, or '
    'prevent any medical condition. Consult a healthcare professional for medical advice.';

Future<void> openPrivacyPolicy() async {
  final uri = Uri.parse(kPrivacyPolicyUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class PrivacyPolicyTextButton extends StatelessWidget {
  const PrivacyPolicyTextButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: openPrivacyPolicy,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF5A7A1A),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(
        'Privacy Policy',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

class PrivacyPolicyConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;

  const PrivacyPolicyConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF5A7A1A),
            side: const BorderSide(color: Color(0xFFEDE5E2), width: 1.5),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF8D6E63).withOpacity(0.9),
                  height: 1.4,
                ),
                children: [
                  const TextSpan(text: 'I have read and agree to the '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(
                      color: Color(0xFF5A7A1A),
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = openPrivacyPolicy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PrivacyPolicyListTile extends StatelessWidget {
  const PrivacyPolicyListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openPrivacyPolicy,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF6F4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.policy_outlined,
                  size: 18,
                  color: Color(0xFFD4A5A5),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3E2723),
                  ),
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: const Color(0xFF8D6E63).withOpacity(0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
