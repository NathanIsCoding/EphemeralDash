Player player;
PVector cam = new PVector();
Level level;
int lastMillis;
boolean spaceDown = false;

float worldUnits = 40;

void setup() {
  size(1000, 800);
  level = new Level("level1.json");
  player = new Player(level.spawn.copy());
  cam = player.project();
  lastMillis = millis();
}

void draw() {
  float dt = min((millis() - lastMillis) / 1000.0, 0.05);
  lastMillis = millis();

  player.update(dt);
  cam.lerp(player.project(), 1 - exp(-dt * 8));

  background(20);
  pushMatrix();
  translate(width / 2 - round(cam.x), height / 2 - round(cam.y));
  level.display(player.shiftT);
  player.display();
  popMatrix();
}

void keyPressed() {
  player.setKey(key, true);
  if (key == ' ' && !spaceDown) {
    spaceDown = true;
    player.toggleShift();
  }
}

void keyReleased() {
  player.setKey(key, false);
  if (key == ' ') spaceDown = false;
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