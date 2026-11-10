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

// Square pyramid sitting on the floor of a grid cell. Not solid: touching it kills
// the player (see Level.touchesSpike), it never blocks movement.
class Spike extends GameObject {
  Spike(PVector pos) {
    this.pos = pos;
  }

  PVector minB() { return new PVector(pos.x, pos.y, pos.z); }
  PVector maxB() { return new PVector(pos.x + 1, pos.y + SPIKE_HEIGHT, pos.z + 1); }

  boolean collides(PVector min, PVector max, boolean is3D) {
    return false;
  }

  // Box vs a hitbox inset from the visual, so grazing the slope or the tip is forgiven
  boolean touches(PVector min, PVector max, boolean is3D) {
    float in = SPIKE_INSET;
    boolean xHit = min.x < pos.x + 1 - in && max.x > pos.x + in;
    boolean yHit = min.y < pos.y + SPIKE_HEIGHT * 0.75 && max.y > pos.y;
    boolean zHit = min.z < pos.z + 1 - in && max.z > pos.z + in;
    return is3D ? (xHit && yHit && zHit) : (xHit && yHit);
  }

  void display() {
    drawPyramid(pos.x, pos.y, pos.z, SPIKE_HEIGHT, 255);
  }
}

final float CANNON_INTERVAL = 2;   // default seconds between shots
final float CANNON_WARN = 0.3;     // the barrel glows for this long before each shot
// Cannon shape, as fractions of the cell: a muzzle disc and a base lip on the firing face
final float CANNON_LIP_H = 0.15;     // height of the lip along the bottom of the face
final float CANNON_OUT = 0.1;        // how far the muzzle and the lip stick out of the face
final float CANNON_MUZZLE_R = 0.35;  // muzzle radius
final float CANNON_BORE_R = 0.24;    // radius of the dark hole in the muzzle
final float CANNON_MUZZLE_Y = CANNON_LIP_H + (1 - CANNON_LIP_H) / 2;  // muzzle centre height: middle of the face above the lip
final float BULLET_SPEED = 5;      // world units per second (the player runs at 8)
final float BULLET_RADIUS = 0.24;
final float BULLET_RANGE = 30;     // a bullet that hits nothing disappears after this distance
final float BULLET_FORGIVE = 0.8;  // bullets test against the player's ball shrunk to this, so near misses survive
final color BARREL_COLOR = #23232A;
final color BULLET_COLOR = #FF7828;

// A block that fires a bullet along DIRS[dir] every interval seconds of level
// time, delayed by offset. The level clock restarts on every respawn, so each attempt
// plays out the same. The body is drawn as a grid cell; only the barrel is drawn here.
// Solid in iso view only: in side view the player passes through it (its bullets
// still hit, though).
class Cannon extends Platform {
  int dir;
  float interval, offset;

  Cannon(PVector pos, int dir, float interval, float offset) {
    super(pos, new PVector(1, 1, 1));
    this.dir = dir;
    this.interval = max(interval, 0.2);  // guard against a zero interval in a level file
    this.offset = offset;
  }

  boolean collides(PVector min, PVector max, boolean is3D) {
    return is3D && super.collides(min, max, is3D);
  }

  // Shots are at offset + k * interval for k = 1, 2, ...; this counts those at or before t
  int shotsBy(float t) {
    return t < offset ? 0 : floor((t - offset) / interval);
  }

  // Adds a bullet for every shot due in (t0, t1]. Each one is moved on by the time
  // since its shot, so the pattern does not depend on the frame rate.
  void fire(float t0, float t1, ArrayList<Bullet> out) {
    for (int k = shotsBy(t0) + 1; k <= shotsBy(t1); k++) {
      Bullet b = new Bullet(muzzle(), PVector.mult(dirVec(), BULLET_SPEED));
      b.update(t1 - (offset + k * interval));
      out.add(b);
    }
  }

  // 0..1, rising over the last CANNON_WARN seconds before the next shot
  float warn(float t) {
    float next = offset + (shotsBy(t) + 1) * interval;
    return constrain(1 - (next - t) / CANNON_WARN, 0, 1);
  }

  PVector dirVec() {
    return new PVector(DIRS[dir][0], DIRS[dir][1], DIRS[dir][2]);
  }

  // Where a bullet starts: centred on the muzzle, just in front of it, so it never touches the cannon
  PVector muzzle() {
    PVector c = PVector.add(pos, new PVector(0.5, CANNON_MUZZLE_Y, 0.5));
    return PVector.add(c, PVector.mult(dirVec(), 0.5 + BULLET_RADIUS + 0.01));
  }

  void displayBarrel(float t) {
    drawCannonBarrel(pos.x, pos.y, pos.z, dir, warn(t));
  }
}

// A cannon's bullet. Flies straight and dies on the first solid thing it touches
// (always tested in 3D: it is a real object in a real lane, whatever the view).
class Bullet {
  PVector pos, vel;
  float travelled = 0;
  boolean alive = true;

  Bullet(PVector pos, PVector vel) {
    this.pos = pos;
    this.vel = vel;
  }

  void update(float dt) {
    pos.add(PVector.mult(vel, dt));
    travelled += vel.mag() * dt;
    if (travelled > BULLET_RANGE || level.collides(minB(), maxB(), true)) alive = false;
  }

  PVector minB() { return new PVector(pos.x - BULLET_RADIUS, pos.y - BULLET_RADIUS, pos.z - BULLET_RADIUS); }
  PVector maxB() { return new PVector(pos.x + BULLET_RADIUS, pos.y + BULLET_RADIUS, pos.z + BULLET_RADIUS); }

  // Sphere vs sphere, against the ball the player is drawn as (not its square hitbox,
  // whose corners stick out past the ball). In side view z is ignored, so a bullet
  // in any lane hits.
  boolean hits(PVector c, float r, boolean is3D) {
    float dx = pos.x - c.x, dy = pos.y - c.y, dz = is3D ? pos.z - c.z : 0;
    float reach = r + BULLET_RADIUS;
    return dx*dx + dy*dy + dz*dz < reach * reach;
  }

  void display() {
    drawBall(pos, BULLET_RADIUS, BULLET_COLOR);
  }
}

// The parts on a cannon's firing face, for the cannon in cell (x, y, z) facing DIRS[dir]:
// a lip along the bottom and a round muzzle above it, both sticking out CANNON_OUT.
// glow (0..1) is the warning before a shot: the bore heats up to the bullet colour.
// Everything is built in the face's own frame (f = out of the face, s = across it,
// u = up), and all sides are drawn, so it looks right from any editor angle.
void drawCannonBarrel(float x, float y, float z, int dir, float glow) {
  PVector f = new PVector(DIRS[dir][0], 0, DIRS[dir][2]);
  PVector s = new PVector(-f.z, 0, f.x);
  PVector u = new PVector(0, 1, 0);
  // bottom centre of the body's firing face, which is recessed CANNON_OUT into the cell
  // (see CellGrid.cellFaces), so the parts end flush with the cell's edge
  PVector face = new PVector(x + 0.5 + f.x * (0.5 - CANNON_OUT), y, z + 0.5 + f.z * (0.5 - CANNON_OUT));

  noLights();
  noStroke();

  // lip: the full width of the face, along its bottom
  cannonBox(face, f, s, u, 0, CANNON_OUT, -0.5, 0.5, 0, CANNON_LIP_H, BARREL_COLOR);

  // muzzle: a short cylinder, then the bore as a disc just in front of its cap
  int n = 24;
  PVector c = PVector.add(face, PVector.mult(u, CANNON_MUZZLE_Y));
  beginShape(QUADS);
  for (int i = 0; i < n; i++) {
    float a0 = TWO_PI * i / n, a1 = TWO_PI * (i + 1) / n, am = (a0 + a1) / 2;
    PVector normal = PVector.add(PVector.mult(s, cos(am)), PVector.mult(u, sin(am)));
    fill(shade(BARREL_COLOR, normal));
    cannonVertex(c, f, s, u, 0, cos(a0) * CANNON_MUZZLE_R, sin(a0) * CANNON_MUZZLE_R);
    cannonVertex(c, f, s, u, CANNON_OUT, cos(a0) * CANNON_MUZZLE_R, sin(a0) * CANNON_MUZZLE_R);
    cannonVertex(c, f, s, u, CANNON_OUT, cos(a1) * CANNON_MUZZLE_R, sin(a1) * CANNON_MUZZLE_R);
    cannonVertex(c, f, s, u, 0, cos(a1) * CANNON_MUZZLE_R, sin(a1) * CANNON_MUZZLE_R);
  }
  endShape();
  cannonDisc(c, f, s, u, CANNON_OUT, CANNON_MUZZLE_R, shade(BARREL_COLOR, f), n);
  cannonDisc(c, f, s, u, CANNON_OUT + 0.002, CANNON_BORE_R, lerpColor(#000000, BULLET_COLOR, glow), n);
}

// A point at (a, b, c) in a cannon face's frame around origin o
void cannonVertex(PVector o, PVector f, PVector s, PVector u, float a, float b, float c) {
  vertex(o.x + f.x * a + s.x * b + u.x * c,
         o.y + f.y * a + s.y * b + u.y * c,
         o.z + f.z * a + s.z * b + u.z * c);
}

// A flat disc facing f, at distance a out from o
void cannonDisc(PVector o, PVector f, PVector s, PVector u, float a, float r, color col, int n) {
  fill(col);
  beginShape(TRIANGLE_FAN);
  cannonVertex(o, f, s, u, a, 0, 0);
  for (int i = 0; i <= n; i++) {
    float t = TWO_PI * i / n;
    cannonVertex(o, f, s, u, a, cos(t) * r, sin(t) * r);
  }
  endShape();
}

// A box spanning [a0, a1] x [b0, b1] x [c0, c1] in a cannon face's frame, all six sides
void cannonBox(PVector o, PVector f, PVector s, PVector u,
               float a0, float a1, float b0, float b1, float c0, float c1, color col) {
  PVector[] basis = { f, s, u };
  beginShape(QUADS);
  // each pair: the side at the low and the high end of one axis
  for (int axis = 0; axis < 3; axis++) {
    for (int side = 0; side < 2; side++) {
      float[] p = { side == 0 ? a0 : a1, side == 0 ? b0 : b1, side == 0 ? c0 : c1 };
      PVector normal = PVector.mult(basis[axis], side == 0 ? -1 : 1);
      fill(shade(col, normal));
      int v = (axis + 1) % 3, w = (axis + 2) % 3;
      float[] vr = { v == 0 ? a0 : v == 1 ? b0 : c0, v == 0 ? a1 : v == 1 ? b1 : c1 };
      float[] wr = { w == 0 ? a0 : w == 1 ? b0 : c0, w == 0 ? a1 : w == 1 ? b1 : c1 };
      float[][] corners = { { vr[0], wr[0] }, { vr[1], wr[0] }, { vr[1], wr[1] }, { vr[0], wr[1] } };
      for (float[] cw : corners) {
        float[] q = new float[3];
        q[axis] = p[axis];
        q[v] = cw[0];
        q[w] = cw[1];
        cannonVertex(o, f, s, u, q[0], q[1], q[2]);
      }
    }
  }
  endShape();
}

// Flat shading without Processing's lights: brighter the more a face points toward
// a fixed light (up, toward the side-view camera, and a little to -x)
color shade(color col, PVector normal) {
  PVector light = new PVector(-0.4, 0.8, 0.5).normalize();
  float k = 0.6 + 0.4 * max(0, normal.dot(light));
  return color(red(col) * k + 30, green(col) * k + 30, blue(col) * k + 30);
}

// Square pyramid on the floor of the cell (x, y, z), tip at height h above it.
// Unlike a box, the +x and -z sides lean up toward the camera, so all four sides
// are drawn and the depth buffer sorts them out. The base faces down and is skipped.
void drawPyramid(float x, float y, float z, float h, float alpha) {
  float x1 = x + 1, z1 = z + 1;
  float ax = x + 0.5, ay = y + h, az = z + 0.5;  // apex
  noLights();  // flat colors per face, like boxes
  noStroke();
  beginShape(TRIANGLES);
  fill(SPIKE_COLORS[0], alpha);  // -x
  vertex(x, y, z);    vertex(x, y, z1);   vertex(ax, ay, az);
  fill(SPIKE_COLORS[1], alpha);  // +z, the face you see in side view
  vertex(x, y, z1);   vertex(x1, y, z1);  vertex(ax, ay, az);
  fill(SPIKE_COLORS[2], alpha);  // +x
  vertex(x1, y, z1);  vertex(x1, y, z);   vertex(ax, ay, az);
  fill(SPIKE_COLORS[3], alpha);  // -z
  vertex(x1, y, z);   vertex(x, y, z);    vertex(ax, ay, az);
  endShape();
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
