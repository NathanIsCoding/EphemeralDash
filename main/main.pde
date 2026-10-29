Player player;
Level level;
int lastMillis;

void setup() {
  size(1000, 800);
  noSmooth();
  level = new Level("level0.txt");
  player = new Player(level.spawn.x, level.spawn.y, level.spawn.z);
  lastMillis = millis();
}

void draw() {
  float dt = (millis() - lastMillis) / 1000.0;
  lastMillis = millis();

  player.update(dt, level);

  background(20);
  pushMatrix();
  translate(width / 2, height / 2);  // camera offset goes here later
  level.display(player.shiftT);
  player.display();
  popMatrix();

  text(frameRate,25,25);
}

void keyPressed() {
  player.setKey(key, true);
  if (key == ' ') player.toggleShift(level);
}

void keyReleased() {
  player.setKey(key, false);
}

// t: 0 = side view, 1 = isometric
PVector worldToScreen(float x, float y, float z, float t) {
  float s = 40;  // pixels per world unit
  PVector side = new PVector(x * s, -y * s);
  PVector iso = new PVector(
    (x - z) * s * 0.5,
    (x + z) * s * 0.25 - y * s * 0.5
  );
  return PVector.lerp(side, iso, t);
}