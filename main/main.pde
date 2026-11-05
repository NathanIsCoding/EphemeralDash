Player player;
PVector cam = new PVector();  // world-space point the camera looks at
Level level;
int lastMillis;
boolean spaceDown = false;
boolean rDown = false;

// Game states: one variable instead of separate booleans
final int PLAYING = 0;
final int PAUSED = 1;
final int MAIN_MENU = 2;
int state = MAIN_MENU;

PauseMenu pauseMenu = new PauseMenu();
MainMenu mainMenu = new MainMenu();

float worldUnits = 40;  // pixels per world unit in side view

// Camera angles at full iso (side view is 0 for both). Pitch 30 degrees gives
// the same 2:1 depth look as the old hand-made iso projection.
final float ISO_YAW = QUARTER_PI;
final float ISO_PITCH = radians(30);
final float ISO_ZOOM = 0.7071;  // iso shows a bit more of the level, like before

void setup() {
  size(1000, 800, P3D);
  smooth(8);
  sphereDetail(24);
  level = new Level("level1.json");
  resetPlayer();
  lastMillis = millis();
}

// put the player back at the level spawn and snap the camera to them
void resetPlayer() {
  player = new Player(level.spawn.copy());
  cam = player.center();
}

void draw() {
  // always advance lastMillis, so resuming does not see one huge frame
  float dt = min((millis() - lastMillis) / 1000.0, 0.05);
  lastMillis = millis();

  if (state == PLAYING) {
    player.update(dt);
    cam.lerp(player.center(), 1 - exp(-dt * 8));
  }

  background(20);
  // Orthographic, so the side view stays perfectly flat. With the default camera
  // this also maps z = 0 straight to pixels, so the menus draw like plain 2D.
  // The huge near/far range keeps the whole level inside the depth range.
  ortho(-width / 2, width / 2, -height / 2, height / 2, -10000, 10000);

  if (state == MAIN_MENU) {
    hint(DISABLE_DEPTH_TEST);
    mainMenu.display();
    return;
  }

  // the world is drawn while playing and paused, so it stays visible (frozen) behind the pause menu
  hint(ENABLE_DEPTH_TEST);
  pushMatrix();
  applyCamera(player.shiftT);
  level.display(player);
  popMatrix();

  // screen-space overlays go on top of the world, so they ignore depth
  noLights();
  hint(DISABLE_DEPTH_TEST);
  if (state == PAUSED) pauseMenu.display();
}

void keyPressed() {
  // always track held keys, so a key released while paused does not stay "stuck" on resume
  player.setKey(key, true);

  if (key == ESC) {
    key = 0;  // stop Processing from closing the sketch
    if (state == PLAYING) state = PAUSED;
    else if (state == PAUSED) state = PLAYING;
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
      // TODO: level creator
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
}

// Sets up the world transform. t: 0 = side view, 1 = iso.
// Afterwards you draw in world units with y up, centered on cam.
// The view shift is a real camera rotation: yaw around y, then tilt down.
void applyCamera(float t) {
  float s = worldUnits * lerp(1, ISO_ZOOM, t);
  translate(width / 2, height / 2, 0);
  scale(s, -s, s);           // world units to pixels, and flip y so +y is up
  rotateX(ISO_PITCH * t);    // tilt to look down on the tops
  rotateY(ISO_YAW * t);      // swing around so the -x faces show
  translate(-cam.x, -cam.y, -cam.z);
}
