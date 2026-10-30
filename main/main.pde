Player player;
PVector cam = new PVector();
Level0 level;
int lastMillis;

float worldUnits = 40;

void setup() {
  size(1000, 800);
  player = new Player(new PVector(0, 0, 0));
  level = new Level0();
  lastMillis = millis();
}

void draw() {
  float dt = (millis() - lastMillis) / 1000.0;
  lastMillis = millis();

  player.update(dt);

  background(20);
  pushMatrix();
  PVector target = player.project();
  cam.lerp(target, 1 - exp(-dt * 8));   // smoothing; raise 8 for a tighter follow
  translate(width / 2 - round(cam.x), height / 2 - round(cam.y));
  level.display(player.shiftT);
  player.display();
  popMatrix();
}

void keyPressed() {
  player.setKey(key, true);
  if (key == ' ') player.toggleShift();
}

void keyReleased() {
  player.setKey(key, false);
}

// t: 0 = side view, 1 = isometric
PVector worldToScreen(float x, float y, float z, float t) {
  PVector side = new PVector(x * worldUnits, -y * worldUnits);
  PVector iso = new PVector(
    (x + z) * worldUnits * 0.5,
    (z - x) * worldUnits * 0.25 - y * worldUnits * 0.5
  );
  return PVector.lerp(side, iso, t);
}