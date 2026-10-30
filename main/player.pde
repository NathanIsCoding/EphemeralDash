class Player {

  PVector pos;          // pos.y = feet
  PVector velocity;
  float radius = 0.5;   // world units

  float maxSpeed = 20;  // safety cap, world units per second
  float accel = 200;    // world units per second squared
  float friction = 6;   // higher = stops faster

  boolean isIso = false;  // in isometric view or not
  float shiftT = 0;       // 0 = side view, 1 = iso

  boolean left, right, fwd, back;

  Player(PVector pos) {
    this.pos = pos.copy();  // copy so the level's spawn is not modified
    velocity = new PVector();
  }

  void toggleShift() {
    isIso = !isIso;
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

    if (back) input.x -= 1;
    if (fwd)  input.x += 1;

    // depth only exists in iso view
    if (isIso) {
      if (left)  input.z -= 1;
      if (right) input.z += 1;
    }

    // ensures diagonals are not faster
    if (input.magSq() > 0) {
      input.normalize();
    }

    // 2. Accelerate
    velocity.add(PVector.mult(input, accel * dt));

    // 3. Friction, cap, and kill leftover depth motion in side view
    velocity.mult(max(0, 1 - friction * dt));
    velocity.limit(maxSpeed);
    if (!isIso) velocity.z = 0;

    // 4. Integrate position (after velocity, so there is no input lag)
    pos.add(PVector.mult(velocity, dt));

    // 5. View blend
    float target = isIso ? 1 : 0;
    shiftT += (target - shiftT) * min(1, dt * 15);
  }

  PVector project() {
    // draw from the center of the circle, not the feet
    return worldToScreen(pos.x, pos.y + radius, pos.z, shiftT);
  }

  void display() {
    PVector p = project();
    noStroke();
    fill(255, 80, 80);
    circle(p.x, p.y, radius * 2 * worldUnits);
  }
}