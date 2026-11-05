class Player extends GameObject {
  // pos = center of the bottom face (x, z centered, y = feet)
  PVector velocity;
  float size = 1;  // cube edge length, world units
  float half = size / 2;

  // gap left when snapping against a surface, so float error does not count as overlap
  final float SKIN = 0.0001;


  float maxSpeed = 15;  // horizontal safety cap, world units per second
  float accel = 150;  // world units per second squared
  float friction = 6;  // higher = stops faster
  float gravity = 30;  // world units per second squared
  float jumpHeight = 2.2;  // world units (peak above take-off)
  float maxFall = 20;  // terminal velocity, world units per second

  boolean isIso = false;  // in isometric view or not
  boolean isGrounded = false; // if on ground
  float shiftT = 0;  // 0 = side view, 1 = iso

  boolean left, right, fwd, back;

  Player(PVector pos) {
    this.pos = pos.copy();  // copy so the level's spawn is not modified
    velocity = new PVector();
  }

  // Returns false (and stays put) if the player would overlap something in the new view
  boolean toggleShift() {
    if (hits(!isIso)) return false;
    isIso = !isIso;
    return true;
  }

  void jump() {
    if (isGrounded) {
      velocity.y = sqrt(2 * gravity * jumpHeight);
      isGrounded = false;
    }
  }

  void setKey(char k, boolean down) {
    switch (Character.toLowerCase(k)) {
      case 'a':
        left = down;
        break;
      case 'd':
        right = down;
        break;
      case 'w':
        fwd = down;
        break;
      case 's':
        back = down;
        break;
    }
  }

  void update(float dt) {
    // 1. Build the input vector from the keys
    PVector input = new PVector();

    if(!isIso) {
      if (right) input.x += 1;
      if (left) input.x -= 1;
    } else { 
      // depth only exists in iso view
      if (fwd) input.x += 1;
      if (back) input.x -= 1;
      if (right) input.z += 1;
      if (left) input.z -= 1;
    }

    // ensures diagonals are not faster
    if (input.magSq() > 0) {
      input.normalize();
    }

    // 2. Accelerate
    velocity.add(PVector.mult(input, accel * dt));

    // 3. Friction and cap on horizontal motion only, so jumps are not damped
    float damp = max(0, 1 - friction * dt);
    velocity.x *= damp;
    velocity.z *= damp;
    PVector flat = new PVector(velocity.x, 0, velocity.z);
    if (flat.mag() > maxSpeed) {
      flat.setMag(maxSpeed);
      velocity.x = flat.x;
      velocity.z = flat.z;
    }
    if (!isIso) { velocity.z = 0; }  // kill leftover depth motion in side view

    // 4. Gravity. Applied every frame, even when grounded,
    //    so the downward collision below keeps confirming we are on the ground.
    velocity.y = max(velocity.y - gravity * dt, -maxFall);

    // 5. Integrate position (after velocity, so there is no input lag)
    // pos.add(PVector.mult(velocity, dt));
    PVector step = PVector.mult(velocity, dt);

    if (moveAxis(0, step.x)) velocity.x = 0;

    isGrounded = false;
    if (moveAxis(1, step.y)) {
      if (step.y < 0) isGrounded = true;  // landed (hitting a ceiling does not count)
      velocity.y = 0;
    }

    if (isIso) {
      if (moveAxis(2, step.z)) velocity.z = 0;
    }

    // 5. View blend
    float target = isIso ? 1 : 0;
    shiftT += (target - shiftT) * min(1, dt * 15);
  }

  // Moves along one axis (0 = x, 1 = y, 2 = z). If that overlaps something,
  // the player is snapped flush against the nearest blocking face instead.
  // Returns true if the move was blocked.
  boolean moveAxis(int axis, float d) {
    if (d == 0) return false;
    float old = getAxis(pos, axis);
    setAxis(pos, axis, old + d);

    ArrayList<GameObject> hit = level.hits(minB(), maxB(), isIso);
    if (hit.isEmpty()) return false;

    // player box spans [pos + lo, pos + hi] on this axis
    float lo = axis == 1 ? 0 : -half;
    float hi = axis == 1 ? size : half;

    float target = old + d;
    for (GameObject o : hit) {
      if (!(o instanceof Platform)) { target = old; break; }  // not a box, so just stay put
      float faceMin = getAxis(o.minB(), axis);
      float faceMax = getAxis(o.maxB(), axis);
      if (d > 0) target = min(target, faceMin - hi - SKIN);
      else       target = max(target, faceMax - lo + SKIN);
    }
    // never get pushed backwards past where we started
    target = d > 0 ? max(target, old) : min(target, old);
    setAxis(pos, axis, target);

    if (hits()) setAxis(pos, axis, old);  // safety net
    return true;
  }

  // World-space center of the hitbox (what the camera follows), not the feet
  PVector center() {
    return new PVector(pos.x, pos.y + half, pos.z);
  }

  PVector minB() { return new PVector(pos.x - half, pos.y, pos.z - half); }
  PVector maxB() { return new PVector(pos.x + half, pos.y + size, pos.z + half); }

  // drawn as a ball inscribed in the hitbox (collision still uses the box)
  void display() {
    drawBall(center(), half, color(255, 80, 80));
  }

  // Separate from display() because it is translucent and must be drawn last
  void displayShadow() {
    drawShadow(pos.x, pos.y, pos.z, half, shiftT);
  }

  // The player is not in level.objects, so nothing tests against it (it uses hits() below instead)
  boolean collides(PVector min, PVector max, boolean is3D) {
    return false;
  }

  boolean hits() {
    return hits(isIso);
  }

  // Collision check as if in the given view (z is ignored in side view)
  boolean hits(boolean is3D) {
    return level.collides(minB(), maxB(), is3D);
  }
}