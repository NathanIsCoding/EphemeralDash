// Base class for everything that lives in the world.
abstract class GameObject {
  PVector pos;

  // World-space bounding box
  abstract PVector minB();
  abstract PVector maxB();

  // Drawn in world coordinates (y up), inside applyCamera()
  abstract void display();

  // Box (min, max) vs this object. Touching is not overlapping.
  // Every subclass must decide; non-solid objects just return false.
  abstract boolean collides(PVector min, PVector max, boolean is3D);
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

  void display() {
    noLights();  // flat colors per face
    drawBox(pos.x, pos.y, pos.z, pos.x + size.x, pos.y + size.y, pos.z + size.z, left, front, top);
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

  void display() {
    drawBall(center, radius, color(255, 200, 60));
  }
}

// Draws the three faces the camera can ever see (-x, +z, top) of the box (x0, y0, z0) to (x1, y1, z1).
// The other three always face away from the camera, and the depth buffer would hide them anyway.
void drawBox(float x0, float y0, float z0, float x1, float y1, float z1,
             color left, color front, color top) {
  beginShape(QUADS);
  fill(left);   // -x, only visible in iso
  vertex(x0, y0, z0);  vertex(x0, y1, z0);  vertex(x0, y1, z1);  vertex(x0, y0, z1);
  fill(front);  // +z, the face you see in side view
  vertex(x0, y0, z1);  vertex(x0, y1, z1);  vertex(x1, y1, z1);  vertex(x1, y0, z1);
  fill(top);    // +y, only visible in iso
  vertex(x0, y1, z0);  vertex(x1, y1, z0);  vertex(x1, y1, z1);  vertex(x0, y1, z1);
  endShape();
}

// Lit sphere. The light is set here (in world space), so balls look round
// while boxes keep their flat face colors.
void drawBall(PVector c, float r, color col) {
  ambientLight(120, 120, 120);
  // Light from above, in front and to the right. The y flip in applyCamera mirrors
  // the world, which reverses Processing's lighting, so the direction is given
  // negated: (0.4, 1, 0.6) here really means traveling (-0.4, -1, -0.6).
  directionalLight(150, 150, 150, 0.4, 1, 0.6);
  fill(col);
  pushMatrix();
  translate(c.x, c.y, c.z);
  sphere(r);
  popMatrix();
  noLights();
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
// (in side view the ground is seen edge-on, so there is nothing to draw on).
// Must be drawn after everything opaque, since it is translucent.
void drawShadow(float x, float bottomY, float z, float r, float t) {
  if (t < 0.01) return;
  float ground = level.groundBelow(x - r, x + r, bottomY, z - r, z + r);
  if (Float.isNaN(ground)) return;

  float h = bottomY - ground;
  float scale = 1 / (1 + 0.35 * h);
  float sr = r * (0.4 + 0.6 * scale);    // never shrinks below 40%
  float alpha = 110 * scale * t;

  noLights();
  noStroke();
  fill(0, alpha);
  hint(DISABLE_DEPTH_MASK);  // still hidden behind things, but does not hide anything itself
  beginShape();
  int n = 24;
  float y = ground + 0.01;   // lifted a hair so it does not z-fight with the ground
  for (int i = 0; i < n; i++) {
    float a = TWO_PI * i / n;
    vertex(x + sr * cos(a), y, z + sr * sin(a));
  }
  endShape(CLOSE);
  hint(ENABLE_DEPTH_MASK);
}
