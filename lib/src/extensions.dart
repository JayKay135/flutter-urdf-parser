import 'package:three_dart/three_dart.dart';

/// This file defines an extension on the [Quaternion] class to add additional functionality.
extension QuaternionExtensions on Quaternion {
  Quaternion operator *(Quaternion q) {
    return Quaternion(
      w * q.x + x * q.w + y * q.z - z * q.y,
      w * q.y - x * q.z + y * q.w + z * q.x,
      w * q.z + x * q.y - y * q.x + z * q.w,
      w * q.w - x * q.x - y * q.y - z * q.z,
    );
  }

  /// Rotates a given [Vector3] by this quaternion.
  ///
  /// The rotation is performed using the operation `q * v * q^-1`,
  /// where `q` is this quaternion, `v` is the vector to rotate,
  /// and `q^-1` is the inverse of this quaternion.
  ///
  /// [point] - The [Vector3] to rotate.
  ///
  /// Returns a new [Vector3] that is the result of the rotation.
  Vector3 rotate(Vector3 point) {
    // Extract the vector part of the quaternion
    Vector3 u = Vector3(x.toDouble(), y.toDouble(), z.toDouble());

    // Extract the scalar part of the quaternion
    double s = w.toDouble();

    // Do the operation q * v * q^-1 (q^-1 is the inverse of the quaternion)
    Vector3 a = u * u.dot(point) * 2;
    Vector3 b = point * (s * s - u.dot(u));
    Vector3 c = u.cross(point) * 2.0 * s;
    Vector3 vprime = a + b + c;

    return vprime;
  }

  /// Returns the inverse of this quaternion.
  ///
  /// The inverse of a quaternion q (q.x, q.y, q.z, q.w) is defined as
  /// (-q.x, -q.y, -q.z, q.w) / (q.x^2 + q.y^2 + q.z^2 + q.w^2).
  Quaternion inverse() {
    num norm = x * x + y * y + z * z + w * w;
    return Quaternion(-x / norm, -y / norm, -z / norm, w / norm);
  }

  /// Multiplies this vector with [vector] and returns the result as a new vector.
  Vector3 multiplied(Vector3 vector) {
    var num = x * 2;
    var num2 = y * 2;
    var num3 = z * 2;
    var num4 = x * num;
    var num5 = y * num2;
    var num6 = z * num3;
    var num7 = x * num2;
    var num8 = x * num3;
    var num9 = y * num3;
    var num10 = w * num;
    var num11 = w * num2;
    var num12 = w * num3;

    Vector3 result = Vector3()..zero();
    result.x = (1 - (num5 + num6)) * vector.x +
        (num7 - num12) * vector.y +
        (num8 + num11) * vector.z;
    result.y = (num7 + num12) * vector.x +
        (1 - (num4 + num6)) * vector.y +
        (num9 - num10) * vector.z;
    result.z = (num8 - num11) * vector.x +
        (num9 + num10) * vector.y +
        (1 - (num4 + num5)) * vector.z;

    return result;
  }
}

/// Extension methods for [Vector3] class.
extension Vector3Extensions on Vector3 {
  Vector3 operator +(dynamic v) {
    if (v is Vector3) {
      return Vector3(x + v.x, y + v.y, z + v.z);
    } else {
      return Vector3(x + v, y + v, z + v);
    }
  }

  Vector3 operator -(dynamic v) {
    if (v is Vector3) {
      return Vector3(x - v.x, y - v.y, z - v.z);
    } else {
      return Vector3(x - v, y - v, z - v);
    }
  }

  Vector3 operator *(dynamic v) {
    if (v is Vector3) {
      return Vector3(x * v.x, y * v.y, z * v.z);
    } else {
      return Vector3(x * v, y * v, z * v);
    }
  }

  Vector3 operator /(dynamic v) {
    if (v is Vector3) {
      return Vector3(x / v.x, y / v.y, z / v.z);
    } else {
      return Vector3(x / v, y / v, z / v);
    }
  }

  /// Returns a [Vector3] instance with all components set to zero.
  Vector3 zero() {
    x = 0.0;
    y = 0.0;
    z = 0.0;

    return this;
  }

  /// Returns a [Vector3] with all components set to 1.
  Vector3 one() {
    x = 1.0;
    y = 1.0;
    z = 1.0;

    return this;
  }
}
