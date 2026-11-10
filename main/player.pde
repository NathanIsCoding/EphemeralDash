class Player extends GameObject {
  // pos = center of the bottom face (x, z centered, y = feet)
  PVector velocity;
  float size = 1;  // cube edge length, world units
  float half = size / 2;

  // gap left when snapping against a surface, so float error does not count as overlap
  final float SKIN = 0.0001;

  boolean alive = true;
  float runSpeed = 10;  // constant forward (+x) speed, world units per second
  float laneSpeed = 1 / 0.10;  // lane change speed: one lane in 0.10 s
  float gravity = 30;  // world units per second squared
  float jumpHeight = 2.2;  // world units (peak above take-off)
  float maxFall = 20;  // terminal velocity, world units per second

  boolean isIso = false;  // in isometric view or not
  boolean isGrounded = false; // if on ground
  float shiftT = 0;  // 0 = side view, 1 = iso

  // Lanes are the z cells; the player rests on a lane's centre (lane + 0.5).
  // During a lane change targetLane differs from lane; if the slide hits
  // something side-on, the player slides back to fromLane (a bump).
  int lane, targetLane, fromLane;

  Player(PVector pos) {
    this.pos = pos.copy();  // copy so the level's spawn is not modified
    velocity = new PVector();
    lane = targetLane = fromLane = floor(this.pos.z);
    this.pos.z = laneZ(lane);  // a spawn on a cell edge snaps to that cell's centre
  }

  float laneZ(int l) {
    return l + 0.5;
  }

  // Returns false (and stays put) if the player would overlap something in the new view
  boolean toggleShift() {
    if (hits(!isIso)) return false;
    isIso = !isIso;
    return true;
  }

  // Jumping only exists in side view; iso is for changing lanes
  void jump() {
    if (!isIso && isGrounded) {
      velocity.y = sqrt(2 * gravity * jumpHeight);
      isGrounded = false;
    }
  }

  // dir: -1 = one lane left (A, -z), +1 = one lane right (D, +z). Iso view only,
  // and ignored while already changing lanes.
  void changeLane(int dir) {
    if (!isIso || targetLane != lane) return;
    fromLane = lane;
    targetLane = lane + dir;
  }

  void update(float dt) {
    // 1. Constant forward run, gravity on y. Gravity is applied every frame, even
    //    when grounded, so the downward collision keeps confirming we are on the ground.
    velocity.x = runSpeed;
    velocity.y = max(velocity.y - gravity * dt, -maxFall);

    // 2. Forward. Anything that stops us head-on is a failed jump.
    if (moveAxis(0, velocity.x * dt, isIso)) {
      alive = false;
      return;
    }

    // 3. Vertical
    isGrounded = false;
    if (moveAxis(1, velocity.y * dt, isIso)) {
      if (velocity.y < 0) isGrounded = true;  // landed (hitting a ceiling does not count)
      velocity.y = 0;
    }

    // 4. Lane change
    updateLane(dt);

    // 5. Spikes, and falling out of the level
    if (level.touchesSpike(minB(), maxB(), isIso)) alive = false;
    if (level.touchesBullet(center(), half * BULLET_FORGIVE, isIso)) alive = false;
    if (pos.y < level.killY) alive = false;

    // 6. View blend
    float target = isIso ? 1 : 0;
    shiftT += (target - shiftT) * min(1, dt * 15);
  }

  // Slides z toward the target lane's centre. A side-on hit turns the slide around,
  // back to the lane we came from. The slide always collides in 3D, even if the
  // view switches to side view mid-slide, so it can never end up inside a block.
  void updateLane(float dt) {
    float target = laneZ(targetLane);
    float dz = target - pos.z;
    if (dz == 0) {
      lane = targetLane;
      return;
    }
    float step = constrain(dz, -laneSpeed * dt, laneSpeed * dt);
    if (moveAxis(2, step, true)) {
      if (targetLane != fromLane) targetLane = fromLane;  // bump: head back
      return;
    }
    if (abs(target - pos.z) < 0.0001) {
      pos.z = target;
      lane = targetLane;
    }
  }

  // Moves along one axis (0 = x, 1 = y, 2 = z). If that overlaps something,
  // the player is snapped flush against the nearest blocking face instead.
  // is3D: collide as in iso view (false ignores z, as in side view).
  // Returns true if the move was blocked.
  boolean moveAxis(int axis, float d, boolean is3D) {
    if (d == 0) return false;
    float old = getAxis(pos, axis);
    setAxis(pos, axis, old + d);

    ArrayList<GameObject> hit = level.hits(minB(), maxB(), is3D);
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

    if (hits(is3D)) setAxis(pos, axis, old);  // safety net
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