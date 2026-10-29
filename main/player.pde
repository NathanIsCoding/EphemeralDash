class Player {
  float posX, posY, posZ;   // posY = height, posZ = depth
  float moveSpeed = 6;      // world units per second
  final float R = 0.25;     // half-size of the collision box, in world units

  boolean isIso = false;
  float shiftT = 0;         // visual blend, 0 = side view, 1 = iso

  boolean left, right, fwd, back;

  // Shift buffering: a blocked shift is retried for a short window
  int shiftRequestedAt = -1;
  final int SHIFT_BUFFER_MS = 120;

  Player(float posX, float posY, float posZ) {
    this.posX = posX;
    this.posY = posY;
    this.posZ = posZ;
  }

  void setKey(char k, boolean down) {
    switch (Character.toLowerCase(k)) {
      case 'a': left = down; break;
      case 'd': right = down; break;
      case 'w': fwd = down; break;
      case 's': back = down; break;
    }
  }

  // Called on the shift key press
  void toggleShift(Level level) {
    if (!trySwitch(level)) {
      shiftRequestedAt = millis();  // blocked, retry for a short window
    }
  }

  // Returns false if the shift is blocked.
  // Entering 3D is always safe. Leaving 3D is only legal if the 2D rule
  // would not put the player inside a solid.
  boolean trySwitch(Level level) {
    if (isIso && level.collides(posX, posY, posZ, R, false)) return false;
    isIso = !isIso;
    shiftRequestedAt = -1;
    return true;
  }

  void update(float dt, Level level) {
    dt = min(dt, 1.0 / 30);  // cap so a lag spike can't tunnel through walls

    // Retry a buffered shift
    if (shiftRequestedAt >= 0) {
      if (millis() - shiftRequestedAt > SHIFT_BUFFER_MS) shiftRequestedAt = -1;
      else trySwitch(level);
    }

    float step = moveSpeed * dt;
    float dx = (right ? step : 0) - (left ? step : 0);
    float dz = isIso ? ((back ? step : 0) - (fwd ? step : 0)) : 0;

    // Resolve each axis separately so the player slides along walls
    if (!level.collides(posX + dx, posY, posZ, R, isIso)) posX += dx;
    if (!level.collides(posX, posY, posZ + dz, R, isIso)) posZ += dz;
    // posY (jump and gravity) goes here later

    float target = isIso ? 1 : 0;
    shiftT += (target - shiftT) * min(1, dt * 15);
  }

  void display() {
    noStroke();

    // Shadow on the ground plane (y = 0), helps read height in iso
    PVector g = worldToScreen(posX, 0, posZ, shiftT);
    fill(0, 90);
    ellipse(g.x, g.y, 20, 10);

    PVector p = worldToScreen(posX, posY, posZ, shiftT);
    fill(255, 80, 80);
    circle(p.x, p.y, 20);
  }
}