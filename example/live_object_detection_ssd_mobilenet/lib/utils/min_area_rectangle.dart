import 'dart:math';

class Point {
  final double x;
  final double y;

  Point(this.x, this.y);

  @override
  String toString() => '($x, $y)';
}

class Rectangle {
  final Point topLeft;
  final Point topRight;
  final Point bottomLeft;
  final Point bottomRight;
  final double area;

  List<Point> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  Rectangle(this.topLeft, this.topRight, this.bottomLeft, this.bottomRight,
      this.area);

  double get width =>
      sqrt(pow(topRight.x - topLeft.x, 2) + pow(topRight.y - topLeft.y, 2));

  double get height =>
      sqrt(pow(bottomLeft.x - topLeft.x, 2) + pow(bottomLeft.y - topLeft.y, 2));

  @override
  String toString() {
    return 'Rectangle(area: $area, corners: [$topLeft, $topRight, $bottomRight, $bottomLeft])';
  }
}

class MinimumBoundingRectangle {
  /// Finds minimum area rectangle containing all "on" points in a 2D mask
  /// mask: 2D list where true/1 represents "on" points
  static Rectangle findMinimumBoundingRectangle(
      List<List<bool>> mask, double scaleX, double scaleY) {
    List<Point> points = _extractPoints(mask, scaleX, scaleY);

    if (points.isEmpty) {
      throw ArgumentError('No "on" points found in mask');
    }

    if (points.length == 1) {
      // Single point - return a tiny rectangle
      Point p = points[0];
      return Rectangle(p, p, p, p, 0.0);
    }

    if (points.length == 2) {
      // Two points - rectangle is just a line
      Point p1 = points[0];
      Point p2 = points[1];
      return Rectangle(p1, p2, p1, p2, 0.0);
    }

    // Find convex hull first
    List<Point> hull = _convexHull(points);

    // return hull;

    // Find minimum area rectangle using rotating calipers
    return _rotatingCalipers(hull);
  }

  /// Extract all "on" points from the mask
  static List<Point> _extractPoints(
      List<List<bool>> mask, double scaleX, double scaleY) {
    List<Point> points = [];

    for (int i = 0; i < mask.length; i++) {
      for (int j = 0; j < mask[i].length; j++) {
        if (mask[i][j]) {
          points.add(Point(j.toDouble() * scaleX, i.toDouble() * scaleY));
        }
      }
    }

    return points;
  }

  /// Compute convex hull using Graham scan
  static List<Point> _convexHull(List<Point> points) {
    if (points.length < 3) return points;

    // Find bottom-most point (or leftmost if tie)
    Point start = points.reduce((a, b) {
      if (a.y < b.y) return a;
      if (a.y > b.y) return b;
      return a.x < b.x ? a : b;
    });

    // Sort points by polar angle with respect to start point
    List<Point> sorted = List.from(points);
    sorted.remove(start);
    sorted.sort((a, b) {
      double angleA = atan2(a.y - start.y, a.x - start.x);
      double angleB = atan2(b.y - start.y, b.x - start.x);
      int cmp = angleA.compareTo(angleB);
      if (cmp == 0) {
        // If same angle, closer point first
        double distA = (pow(a.x - start.x, 2) as double) +
            (pow(a.y - start.y, 2) as double);
        double distB = (pow(b.x - start.x, 2) as double) +
            (pow(b.y - start.y, 2) as double);
        return distA.compareTo(distB);
      }
      return cmp;
    });

    // Build convex hull
    List<Point> hull = [start];

    for (Point p in sorted) {
      while (hull.length > 1 &&
          _crossProduct(hull[hull.length - 2], hull[hull.length - 1], p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }

    return hull;
  }

  /// Cross product for orientation test
  static double _crossProduct(Point a, Point b, Point c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }

  /// Find minimum area rectangle using rotating calipers algorithm
  static Rectangle _rotatingCalipers(List<Point> hull) {
    int n = hull.length;
    if (n < 3) {
      // Degenerate case
      if (n == 1) {
        Point p = hull[0];
        return Rectangle(p, p, p, p, 0.0);
      } else {
        Point p1 = hull[0], p2 = hull[1];
        return Rectangle(p1, p2, p1, p2, 0.0);
      }
    }

    double minArea = double.infinity;
    Rectangle? bestRect;

    for (int i = 0; i < n; i++) {
      Point p1 = hull[i];
      Point p2 = hull[(i + 1) % n];

      // Edge vector
      double dx = p2.x - p1.x;
      double dy = p2.y - p1.y;
      double edgeLength = sqrt(dx * dx + dy * dy);

      if (edgeLength == 0) continue;

      // Unit vectors
      double ux = dx / edgeLength;
      double uy = dy / edgeLength;
      double vx = -uy; // Perpendicular
      double vy = ux;

      // Project all points onto the edge direction and perpendicular
      double minU = double.infinity, maxU = -double.infinity;
      double minV = double.infinity, maxV = -double.infinity;

      for (Point p in hull) {
        double u = (p.x - p1.x) * ux + (p.y - p1.y) * uy;
        double v = (p.x - p1.x) * vx + (p.y - p1.y) * vy;

        minU = min(minU, u);
        maxU = max(maxU, u);
        minV = min(minV, v);
        maxV = max(maxV, v);
      }

      double width = maxU - minU;
      double height = maxV - minV;
      double area = width * height;

      if (area < minArea) {
        minArea = area;

        // Calculate rectangle corners
        Point corner1 =
            Point(p1.x + minU * ux + minV * vx, p1.y + minU * uy + minV * vy);
        Point corner2 =
            Point(p1.x + maxU * ux + minV * vx, p1.y + maxU * uy + minV * vy);
        Point corner3 =
            Point(p1.x + maxU * ux + maxV * vx, p1.y + maxU * uy + maxV * vy);
        Point corner4 =
            Point(p1.x + minU * ux + maxV * vx, p1.y + minU * uy + maxV * vy);

        bestRect = Rectangle(corner1, corner2, corner4, corner3, area);
      }
    }

    return bestRect ?? Rectangle(hull[0], hull[0], hull[0], hull[0], 0.0);
  }
}
