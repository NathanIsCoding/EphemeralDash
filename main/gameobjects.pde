// Base class for everything that lives in the world and gets depth-sorted.
abstract class GameObject {
  PVector pos;

  // World-space bounding box, used for draw ordering
  abstract PVector minB();
  abstract PVector maxB();

  abstract void display(float t);

  // Box (min, max) vs this object. Touching is not overlapping.
  // Every subclass must decide; non-solid objects just return false.
  abstract boolean collides(PVector min, PVector max, boolean is3D);

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

  // Box vs box. Strict comparisons, so boxes sharing a face do not collide.
  // In side view z is ignored.
  boolean collides(PVector min, PVector max, boolean is3D) {
    boolean xHit = min.x < pos.x + size.x && max.x > pos.x;
    boolean yHit = min.y < pos.y + size.y && max.y > pos.y;
    boolean zHit = min.z < pos.z + size.z && max.z > pos.z;
    return is3D ? (xHit && yHit && zHit) : (xHit && yHit);
  }

  // Point vs box
  boolean contains(PVector p, boolean is3D) {
    boolean inXY = p.x >= pos.x && p.x <= pos.x + size.x && p.y >= pos.y && p.y <= pos.y + size.y;
    boolean inZ = p.z >= pos.z && p.z <= pos.z + size.z;
    return is3D ? (inXY && inZ) : inXY;
  }

  void display(float t) {
    drawBox(pos.x, pos.y, pos.z, pos.x + size.x, pos.y + size.y, pos.z + size.z, left, front, top, t);
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

  // Sphere vs box: distance from the dot's center to the closest point of the box
  boolean collides(PVector min, PVector max, boolean is3D) {
    float dx = center.x - constrain(center.x, min.x, max.x);
    float dy = center.y - constrain(center.y, min.y, max.y);
    float distSq = dx*dx + dy*dy;
    if (is3D) {
      float dz = center.z - constrain(center.z, min.z, max.z);
      distSq += dz*dz;
    }
    return distSq < radius * radius;
  }

  void display(float t) {
    PVector s = worldToScreen(center.x, center.y, center.z, t);
    noStroke();
    fill(255, 200, 60);
    circle(s.x, s.y, radius * 2 * worldUnits);
  }
}

// Draws the three camera-facing faces of the box (x0, y0, z0) to (x1, y1, z1)
void drawBox(float x0, float y0, float z0, float x1, float y1, float z1,
             color left, color front, color top, float t) {
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

// PVector component by index (0 = x, 1 = y, 2 = z), so axis code can be written once
float getAxis(PVector v, int axis) {
  return axis == 0 ? v.x : axis == 1 ? v.y : v.z;
}

void setAxis(PVector v, int axis, float value) {
  if (axis == 0) v.x = value;
  else if (axis == 1) v.y = value;
  else v.z = value;
}

// Soft round shadow on the ground under a ball centered over (x, z) with radius r,
// whose bottom is at bottomY. Ground is found under the whole square footprint
// (matching the hitbox), so the shadow stays while standing on an edge.
// Shrinks and fades as the ball rises, and fades in with the view blend
// (in side view the ground has no visible top, so there is nothing to draw on).
void drawShadow(float x, float bottomY, float z, float r, float t) {
  if (t < 0.01) return;
  float ground = level.groundBelow(x - r, x + r, bottomY, z - r, z + r);
  if (Float.isNaN(ground)) return;

  float h = bottomY - ground;
  float scale = 1 / (1 + 0.35 * h);
  float sr = r * (0.4 + 0.6 * scale);    // never shrinks below 40%
  float alpha = 110 * scale * t;

  noStroke();
  fill(0, alpha);
  beginShape();
  int n = 24;
  for (int i = 0; i < n; i++) {
    float a = TWO_PI * i / n;
    // project a circle lying flat on the ground, so it is correct at any view blend
    PVector p = worldToScreen(x + sr * cos(a), ground, z + sr * sin(a), t);
    vertex(p.x, p.y);
  }
  endShape(CLOSE);
}
