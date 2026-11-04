class Player extends GameObject {
  // pos.y = feet
  PVector velocity;
  float radius = 0.5;  // world units

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

    pos.x += step.x;
    if (hits()) { pos.x -= step.x; velocity.x = 0; }

    pos.y += step.y;
    isGrounded = false;
    if (hits()) {
      pos.y -= step.y;
      if (step.y < 0) isGrounded = true;  // landed (hitting a ceiling does not count)
      velocity.y = 0;
    }

    if (isIso) {
      pos.z += step.z;
      if (hits()) { pos.z -= step.z; velocity.z = 0; }
    }

    // 5. View blend
    float target = isIso ? 1 : 0;
    shiftT += (target - shiftT) * min(1, dt * 15);
  }

  PVector project() {
    // draw from the center of the circle, not the feet
    return worldToScreen(pos.x, pos.y + radius, pos.z, shiftT);
  }

  PVector minB() { return new PVector(pos.x - radius, pos.y, pos.z - radius); }
  PVector maxB() { return new PVector(pos.x + radius, pos.y + 2 * radius, pos.z + radius); }

  void display(float t) {
    drawShadow(pos.x, pos.y, pos.z, radius, t);
    PVector p = worldToScreen(pos.x, pos.y + radius, pos.z, t);
    noStroke();
    fill(255, 80, 80);
    circle(p.x, p.y, radius * 2 * worldUnits);
  }

  // The player is not in level.objects, so nothing tests against it (it uses hits() below instead)
  boolean collides(PVector center, float r, boolean is3D) {
    return false;
  }

  boolean hits() {
    return hits(isIso);
  }

  // Collision check as if in the given view (z is ignored in side view)
  boolean hits(boolean is3D) {
    PVector center = new PVector(pos.x, pos.y + radius, pos.z);
    return level.collides(center, (radius - 0.05), is3D);
  }
}