import 'package:flutter/foundation.dart';
import '../../core/constants/app_constants.dart';

/// User model supporting farmer, buyer, and admin roles.
@immutable
class UserModel {
  final String id;
  final String name;
  final String? email;
  final String role; // 'farmer' | 'buyer' | 'admin'
  final bool isVerified;
  final String? mobileNumber;
  final String? district;
  final String? postalCode;
  final String? address;
  final String? companyName;
  final String? profileImageUrl;
  final bool profileCompleted;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.name,
    required this.role,
    required this.isVerified,
    required this.createdAt,
    this.email,
    this.mobileNumber,
    this.district,
    this.postalCode,
    this.address,
    this.companyName,
    this.profileImageUrl,
    this.profileCompleted = false,
  });

  bool get isFarmer => role == AppConstants.roleFarmer;
  bool get isBuyer => role == AppConstants.roleBuyer;
  bool get isAdmin => role == AppConstants.roleAdmin;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString(),
      role: json['role']?.toString() ?? AppConstants.roleBuyer,
      isVerified: json['is_verified'] as bool? ?? false,
      mobileNumber: json['mobile_number']?.toString(),
      district: json['district']?.toString(),
      postalCode: json['postal_code']?.toString(),
      address: json['address']?.toString(),
      companyName: json['company_name']?.toString(),
      profileImageUrl: json['profile_image']?.toString(),
      profileCompleted: json['profile_completed'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (email != null) 'email': email,
        'role': role,
        'is_verified': isVerified,
        if (mobileNumber != null) 'mobile_number': mobileNumber,
        if (district != null) 'district': district,
        if (postalCode != null) 'postal_code': postalCode,
        if (address != null) 'address': address,
        if (companyName != null) 'company_name': companyName,
        if (profileImageUrl != null) 'profile_image': profileImageUrl,
        'profile_completed': profileCompleted,
        'created_at': createdAt.toIso8601String(),
      };

  UserModel copyWith({
    String? name,
    String? email,
    bool? isVerified,
    String? mobileNumber,
    String? district,
    String? postalCode,
    String? address,
    String? companyName,
    String? profileImageUrl,
    bool? profileCompleted,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role,
      isVerified: isVerified ?? this.isVerified,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      district: district ?? this.district,
      postalCode: postalCode ?? this.postalCode,
      address: address ?? this.address,
      companyName: companyName ?? this.companyName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      createdAt: createdAt,
    );
  }
}
