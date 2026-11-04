Player player;
PVector cam = new PVector();
Level level;
int lastMillis;
boolean spaceDown = false;
boolean rDown = false;

// Game states: one variable instead of separate booleans
final int PLAYING = 0;
final int PAUSED = 1;
final int MAIN_MENU = 2;
final int EDITOR = 3;
int state = MAIN_MENU;

String levelFile = "level1.json";
Editor editor;

PauseMenu pauseMenu = new PauseMenu();
MainMenu mainMenu = new MainMenu();

float worldUnits = 40;

void setup() {
  size(1000, 800);
  level = new Level(levelFile);
  resetPlayer();
  lastMillis = millis();
}

// put the player back at the level spawn and snap the camera to them
void resetPlayer() {
  player = new Player(level.spawn.copy());
  cam = player.project();
}

void draw() {
  // always advance lastMillis, so resuming does not see one huge frame
  float dt = min((millis() - lastMillis) / 1000.0, 0.05);
  lastMillis = millis();

  if (state == PLAYING) {
    player.update(dt);
    cam.lerp(player.project(), 1 - exp(-dt * 8));
  }

  background(20);

  if (state == MAIN_MENU) {
    mainMenu.display();
    return;
  }

  if (state == EDITOR) {
    editor.update(dt);
    editor.display();
    return;
  }

  // the world is drawn while playing and paused, so it stays visible (frozen) behind the pause menu
  pushMatrix();
  translate(width / 2 - round(cam.x), height / 2 - round(cam.y));
  level.display(player.shiftT, player);  // draws the player in depth order
  popMatrix();

  if (state == PAUSED) pauseMenu.display();
}

void keyPressed() {
  // always track held keys, so a key released while paused does not stay "stuck" on resume
  player.setKey(key, true);

  if (key == ESC) {
    key = 0;  // stop Processing from closing the sketch
    if (state == PLAYING) state = PAUSED;
    else if (state == PAUSED) state = PLAYING;
    else if (state == EDITOR) {
      // save, then reload so "Play" uses the edited level
      editor.save();
      level = new Level(levelFile);
      resetPlayer();
      state = MAIN_MENU;
    }
    return;
  }

  if (state == EDITOR) {
    editor.keyPressed();
    return;
  }

  if (state == MAIN_MENU) {
    String choice = mainMenu.keyPressed();
    if (choice == null) return;

    if (choice.equals("Play")) {
      resetPlayer();
      state = PLAYING;
    } else if (choice.equals("Settings")) {
      // TODO: settings menu
    } else if (choice.equals("Level Creator")) {
      editor = new Editor(levelFile);
      state = EDITOR;
    } else if (choice.equals("Quit")) {
      exit();
    }
    return;
  }

  if (state == PLAYING) {
    // the down flags ignore key repeat, so holding a key only triggers once
    if (key == ' ' && !spaceDown) {
      spaceDown = true;
      player.jump();
    }

    if ((key == 'r' || key == 'R') && !rDown) {
      rDown = true;
      player.toggleShift();
    }
  } else if (state == PAUSED) {
    String choice = pauseMenu.keyPressed();
    if (choice == null) return;

    if (choice.equals("Resume")) {
      state = PLAYING;
    } else if (choice.equals("Settings")) {
      // TODO: settings menu
    } else if (choice.equals("Main Menu")) {
      pauseMenu.selected = 0;  // highlight "Resume" next time the game is paused
      state = MAIN_MENU;
    } else if (choice.equals("Quit")) {
      exit();
    }
  }
}

void keyReleased() {
  player.setKey(key, false);
  if (key == ' ') spaceDown = false;
  if (key == 'r' || key == 'R') rDown = false;
  if (state == EDITOR) editor.keyReleased();
}

void mousePressed() {
  if (state == EDITOR) editor.mousePressed();
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