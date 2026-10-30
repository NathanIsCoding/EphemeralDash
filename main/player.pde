class Player { 

  PVector input;
  PVector pos;
  PVector velocity;
  
  float maxSpeed = 10;     // safety cap, world units per second
  float accel = 100;       // world units per second squared (was moveSpeed)
  float friction = 6;     // higher = stops faster

  float scale = 40;         // pixels per world unit
  boolean isIso = false;    // Is in isometric view or not)
  float shiftT = 0;         // 0 = side view, 1 = iso

  boolean left, right, fwd, back;



  Player(PVector pos) { 
    this.pos = pos;
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

    if (back)  {
      input.x -= 1;
    }

    if (fwd) {
      input.x += 1;
    }

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
    return worldToScreen(pos.x, pos.y, pos.z, shiftT);
  }

  void display() {
    PVector p = project();
    noStroke();
    fill(255, 80, 80);
    circle(p.x, p.y, 30);
  }
}