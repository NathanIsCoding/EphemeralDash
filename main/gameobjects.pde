// Base class for everything that lives in the world and gets depth-sorted.
abstract class GameObject {
  PVector pos;

  // World-space bounding box, used for draw ordering
  abstract PVector minB();
  abstract PVector maxB();

  abstract void display(float t);

  // Sphere vs this object. Non-solid objects can leave this as false.
  boolean collides(PVector center, float r, boolean is3D) {
    return false;
  }

  // Rough far-to-near key, only used to break ties the depth rule leaves open
  float depthKey() {
    PVector a = minB(), b = maxB();
    return -(a.x + b.x) * 0.5 + (a.z + b.z) * 0.5 + (a.y + b.y) * 0.5;
  }
}

class Platform extends GameObject {
  PVector size;
  color left = color(40, 90, 170);
  color front = color(60, 120, 210);
  color top = color(90, 150, 240);

  Platform(PVector pos, PVector size) {
    this.pos = pos;
    this.size = size;
  }

  PVector minB() { return pos; }
  PVector maxB() { return PVector.add(pos, size); }

  boolean collides(PVector center, float r, boolean is3D) {
    float cx = constrain(center.x, pos.x, pos.x + size.x);
    float cy = constrain(center.y, pos.y, pos.y + size.y);
    float dx = center.x - cx;
    float dy = center.y - cy;
    float distSq = dx*dx + dy*dy;

    if (is3D) {
      float cz = constrain(center.z, pos.z, pos.z + size.z);
      float dz = center.z - cz;
      distSq += dz*dz;
    }
    return distSq <= r*r;
  }

  // Box vs box
  boolean overlaps(PVector otherPos, PVector otherSize, boolean is3D) {
    boolean xHit = otherPos.x < pos.x + size.x && otherPos.x + otherSize.x > pos.x;
    boolean yHit = otherPos.y < pos.y + size.y && otherPos.y + otherSize.y > pos.y;
    boolean zHit = otherPos.z < pos.z + size.z && otherPos.z + otherSize.z > pos.z;
    return is3D ? (xHit && yHit && zHit) : (xHit && yHit);
  }

  // Point vs box
  boolean contains(PVector p, boolean is3D) {
    boolean inXY = p.x >= pos.x && p.x <= pos.x + size.x && p.y >= pos.y && p.y <= pos.y + size.y;
    boolean inZ = p.z >= pos.z && p.z <= pos.z + size.z;
    return is3D ? (inXY && inZ) : inXY;
  }

  void display(float t) {
    float x0 = pos.x, x1 = pos.x + size.x;
    float y0 = pos.y, y1 = pos.y + size.y;
    float z0 = pos.z, z1 = pos.z + size.z;

    // Left face (-x), only visible in iso
    fill(left);
    quadFace(x0, y0, z0,  x0, y1, z0,  x0, y1, z1,  x0, y0, z1,  t);

    // Front face (+z), the face you see in side view
    fill(front);
    quadFace(x0, y0, z1,  x0, y1, z1,  x1, y1, z1,  x1, y0, z1,  t);

    // Top face, only visible in iso
    fill(top);
    quadFace(x0, y1, z0,  x1, y1, z0,  x1, y1, z1,  x0, y1, z1,  t);
  }

  void quadFace(float ax, float ay, float az, float bx, float by, float bz, float cx, float cy, float cz, float dx, float dy, float dz, float t) {
    PVector a = worldToScreen(ax, ay, az, t);
    PVector b = worldToScreen(bx, by, bz, t);
    PVector c = worldToScreen(cx, cy, cz, t);
    PVector d = worldToScreen(dx, dy, dz, t);
    quad(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y);
  }
}

class Cube extends Platform {
  Cube(PVector pos, PVector size) {
    super(pos, size);
    left  = color(170, 60, 60);
    front = color(210, 80, 80);
    top   = color(240, 120, 120);
  }
}

class Dot extends GameObject {
  float radius;
  PVector center;  // pos is the grid cell corner (like cubes), the dot sits in the middle

  Dot(PVector pos, float radius) {
    this.pos = pos;
    this.radius = radius;
    center = PVector.add(pos, new PVector(0.5, 0.5, 0.5));
  }

  PVector minB() { return new PVector(center.x - radius, center.y - radius, center.z - radius); }
  PVector maxB() { return new PVector(center.x + radius, center.y + radius, center.z + radius); }

  // Circle/sphere vs dot
  boolean collides(PVector p, float otherRadius, boolean is3D) {
    float d = is3D
      ? center.dist(p)
      : dist(center.x, center.y, p.x, p.y);   // ignore z in 2D
    return d <= radius + otherRadius;
  }

  void display(float t) {
    fill(255, 200, 60);
    PVector s = worldToScreen(center.x, center.y, center.z, t);
    circle(s.x, s.y, radius * 2 * worldUnits);
  }
}
