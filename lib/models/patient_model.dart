import 'package:flutter/material.dart';

class Patient {
  final String name;
  final String location;
  final List<String> reminders;
  final Color avatarColor;

  Patient({
    required this.name,
    required this.location,
    List<String>? reminders,
    required this.avatarColor,
  }) : reminders = reminders ?? [];
}