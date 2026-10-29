class Player { 

  float posX, posY, posZ;   // posY = height, posZ = depth
  float moveSpeed = 6;      // world units per second
  float scale = 40;         // pixels per world unit
  boolean isIso = false;    // Is in isometric view or not)
  float shiftT = 0;         // 0 = side view, 1 = iso

  boolean left, right, fwd, back;

  PVector pos;
  PVector velocity;
  float maxSpeed = 6;

  Player(PVector pos) { 
    this.pos = pos;
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
    float step = moveSpeed * dt;
    if (left) { 
      velocity.x -= step; } 
    else { 
      if(velocity.x < 0) { 
        velocity.x += 0.01;
      }
    }
    if (right) { velocity.x += step; }

    if (isIso) { // depth movement only exists in 3D mode
      if (fwd) { posZ -= step; }
      if (back) { posZ += step; }

      // Compount movements
      if(fwd && right) { }
      if(fwd && left) { }

      if(back && right) { }
      if(back && left) { }
    }
    float target = isIso ? 1 : 0;
    shiftT += (target - shiftT) * min(1, dt * 15);
  }

  PVector project() {
    return worldToScreen(velocity.x, velocity.y, velocity.z, shiftT);
  }

  void display() {
    PVector p = project();
    noStroke();
    fill(255, 80, 80);
    circle(p.x, p.y, 30);
  }
}