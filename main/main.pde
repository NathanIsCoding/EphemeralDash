Player player;
PVector cam = new PVector();  // world-space point the camera looks at
Level level;
int lastMillis;

final float LOOK_AHEAD = 4;  // world units the camera looks ahead of the player, in +x

// Game states: one variable instead of separate booleans
final int PLAYING = 0;
final int PAUSED = 1;
final int MAIN_MENU = 2;
final int EDITOR = 3;
final int LEVEL_SELECT = 4;
final int WON = 5;
final int DEAD = 6;
final int SETTINGS = 7;

final int DEATH_DELAY = 3000;  // ms the "You Died" screen shows before the restart
int deathMillis;

int state = MAIN_MENU;

String levelFile = "level1.json";
Editor editor;

PauseMenu pauseMenu = new PauseMenu();
MainMenu mainMenu = new MainMenu();
LevelSelect levelSelect = new LevelSelect();
WinMenu winMenu = new WinMenu();
Music music;  // made in setup(), after Minim
DeathMenu deathMenu = new DeathMenu();
SettingsMenu settingsMenu = new SettingsMenu();
Keybinds keybinds;  // made in setup(): it needs DEFAULT_KEYS from settings.pde, which is set up after this tab's globals

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
  keybinds = new Keybinds();
  minim = new Minim(this);
  music = new Music();
  loadSettings();  // keys and music volume
  level = new Level(levelFile);
  resetPlayer();
  lastMillis = millis();
}

// put the player back at the level spawn and snap the camera to them
void resetPlayer() {
  player = new Player(level.spawn.copy());
  level.reset();
  cam = camTarget();
}

// Where the camera wants to be: a little ahead of the player, so you see what is coming
PVector camTarget() {
  return PVector.add(player.center(), new PVector(LOOK_AHEAD, 0, 0));
}

void draw() {
  // always advance lastMillis, so resuming does not see one huge frame
  float dt = min((millis() - lastMillis) / 1000.0, 0.05);
  lastMillis = millis();

  if (state == PLAYING) {
    level.update(dt);
    player.update(dt);
    if (!player.alive) {
      state = DEAD;
      deathMillis = millis();
      music.stop();
      deathMenu.open(testing);
    }
    else if (player.pos.x >= level.goal.x) {
      // crossing the goal's line counts, in any lane and either view
      if (testing) {
        stopTest();
        editor.flash("Reached the goal in " + formatTime(level.clock));
      } else {
        winMenu.open(levelFile);
        state = WON;
      }
    }
    cam.lerp(camTarget(), 1 - exp(-dt * 8));
  } else if (state == DEAD && millis() - deathMillis >= DEATH_DELAY) {
    startAttempt();
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

  if (state == LEVEL_SELECT) {
    hint(DISABLE_DEPTH_TEST);
    levelSelect.display();
    return;
  }

  // opened from the main menu there is no world behind it
  if (state == SETTINGS && settingsMenu.returnState == MAIN_MENU) {
    hint(DISABLE_DEPTH_TEST);
    settingsMenu.display();
    return;
  }

  if (state == EDITOR) {
    // the editor sets up its own depth testing for the world and its overlays
    editor.update(dt);
    editor.display();
    return;
  }

  // the world is drawn while playing and paused, so it stays visible (frozen) behind the pause menu
  hint(ENABLE_DEPTH_TEST);
  pushMatrix();
  applyCamera(player.shiftT);
  // while paused dt is 0 so block fading freezes too
  level.display(player, state == PLAYING ? dt : 0);  popMatrix();

  // screen-space overlays go on top of the world, so they ignore depth
  noLights();
  hint(DISABLE_DEPTH_TEST);
  if (state == PAUSED) pauseMenu.display();
  if (state == WON) winMenu.display();
  if (state == DEAD) displayDeath();
  if (state == SETTINGS) settingsMenu.display();
  if (testing) {
    flush();  // so the world's outlines cannot show through the bar (see Editor.display)
    drawTestBar();
  }
}

// play-testing from the editor

boolean testing = false;  // playing the editor's level; Esc / Stop goes back to the editor
final float TEST_BTN_X = 12, TEST_BTN_Y = 12, TEST_BTN_W = 96, TEST_BTN_H = 34;

PVector testStart;  // where the play-test starts, or null for the spawn

// Plays the level as it is in the editor, unsaved changes included. from is the
// player's starting point (feet, centred on its lane), or null for the spawn.
void startTest(PVector from) {
  level = new Level(editor.levelJSON(), levelFile);
  testing = true;
  testStart = from;
  startAttempt();
}

void stopTest() {
  testing = false;
  music.stop();
  state = EDITOR;
}

boolean overStopButton() {
  return mouseX >= TEST_BTN_X && mouseX < TEST_BTN_X + TEST_BTN_W
      && mouseY >= TEST_BTN_Y && mouseY < TEST_BTN_Y + TEST_BTN_H;
}

// m:ss.ss
String formatTime(float s) {
  int m = floor(s / 60);
  return m + ":" + nf(s - m * 60, 2, 2);
}

// Stop button, then the attempt's time and the player's distance along the level.
// The run speed is constant, so the time is also how far into the music this point is.
void drawTestBar() {
  boolean hover = overStopButton();
  noStroke();
  fill(0, 170);
  rect(TEST_BTN_X - 4, TEST_BTN_Y - 4, 360, TEST_BTN_H + 8, 8);

  fill(hover ? color(255, 80, 80, 90) : color(255, 30));
  stroke(hover ? color(255, 80, 80) : color(255, 80));
  strokeWeight(1);
  rect(TEST_BTN_X, TEST_BTN_Y, TEST_BTN_W, TEST_BTN_H, 6);
  noStroke();
  editor.drawIcon("stop", TEST_BTN_X + 20, TEST_BTN_Y + TEST_BTN_H / 2);
  fill(255);
  textAlign(LEFT, CENTER);
  textSize(16);
  text("Stop", TEST_BTN_X + 36, TEST_BTN_Y + TEST_BTN_H / 2 - 1);

  fill(255, 200, 60);
  text(formatTime(level.clock), TEST_BTN_X + TEST_BTN_W + 16, TEST_BTN_Y + TEST_BTN_H / 2 - 1);
  fill(170);
  text("x " + nf(player.pos.x, 1, 1) + "   Esc to stop", TEST_BTN_X + TEST_BTN_W + 100, TEST_BTN_Y + TEST_BTN_H / 2 - 1);
}

// Frozen world behind the death menu and a countdown to the restart
void displayDeath() {
  int left = ceil((DEATH_DELAY - (millis() - deathMillis)) / 1000.0);
  deathMenu.display(max(left, 1));
}

void keyPressed() {
  // first, so Esc can cancel a rebind and any other key can be bound
  if (state == SETTINGS) {
    if (settingsMenu.keyPressed()) state = settingsMenu.returnState;
    if (key == ESC) key = 0;  // stop Processing from closing the sketch
    return;
  }

  if (key == ESC) {
    key = 0;  // stop Processing from closing the sketch
    if (testing) stopTest();  // straight back to the editor, no pause menu
    else if (state == PLAYING) pauseGame();
    else if (state == PAUSED) resumeGame();
    else if (state == EDITOR) editor.escape();
    else if (state == LEVEL_SELECT) state = MAIN_MENU;
    else if (state == WON || state == DEAD) openLevelSelect(false);
    return;
  }

  if (state == DEAD) {
    chooseDeath(deathMenu.keyPressed());
    return;
  }

  if (state == EDITOR) {
    editor.keyPressed();
    return;
  }

  if (state == LEVEL_SELECT) {
    String file = levelSelect.keyPressed();
    if (file != null) chooseLevel(file);
    return;
  }

  if (state == WON) {
    chooseWin(winMenu.keyPressed());
    return;
  }

  if (state == MAIN_MENU) {
    chooseMain(mainMenu.keyPressed());
    return;
  }

  if (state == PLAYING) {
    // keybinds.pressed() ignores key repeat, so holding a key only triggers once
    int action = keybinds.pressed();
    if (action == ACT_JUMP) player.jump();
    if (action == ACT_SHIFT) player.toggleShift();
    // one lane per tap (iso only; the player ignores it in side view).
    // Left/right are relative to the run direction (+x): left is -z, right is +z
    if (action == ACT_LANE_LEFT) player.changeLane(-1);
    if (action == ACT_LANE_RIGHT) player.changeLane(1);
  } else if (state == PAUSED) {
    choosePause(pauseMenu.keyPressed());
  }
}

// What each menu's items do. Called with the item picked by key or click (or null for none).

void chooseMain(String choice) {
  if (choice == null) return;
  if (choice.equals("Play")) openLevelSelect(false);
  else if (choice.equals("Settings")) openSettings();
  else if (choice.equals("Level Creator")) openLevelSelect(true);
  else if (choice.equals("Quit")) exit();
}

void choosePause(String choice) {
  if (choice == null) return;
  if (choice.equals("Resume")) {
    resumeGame();
  } else if (choice.equals("Level Select")) {
    pauseMenu.selected = 0;
    openLevelSelect(false);
  } else if (choice.equals("Settings")) {
    openSettings();
  } else if (choice.equals("Main Menu")) {
    pauseMenu.selected = 0;  // highlight "Resume" next time the game is paused
    music.stop();
    state = MAIN_MENU;
  } else if (choice.equals("Quit")) {
    exit();
  }
}

void chooseWin(String choice) {
  if (choice == null) return;
  if (choice.equals("Next Level")) playLevel(winMenu.nextFile);
  else if (choice.equals("Level Select")) openLevelSelect(false);
}

void chooseDeath(String choice) {
  if (choice == null) return;
  if (choice.equals("Retry")) {
    startAttempt();
  } else if (choice.equals("Level Select")) {
    openLevelSelect(false);
  } else if (choice.equals("Back to Editor")) {
    stopTest();
  }
}

// Settings goes back to whichever menu opened it
void openSettings() {
  settingsMenu.open(state);
  state = SETTINGS;
}

void openLevelSelect(boolean editMode) {
  music.stop();
  levelSelect.open(editMode);
  state = LEVEL_SELECT;
}

// The level select picked a file: play it, or open it in the editor
// (a file that does not exist yet starts out as a new level there)
void chooseLevel(String file) {
  if (levelSelect.editMode) {
    levelFile = file;
    editor = new Editor(levelFile);
    state = EDITOR;
  } else {
    playLevel(file);
  }
}

void playLevel(String file) {
  levelFile = file;
  level = new Level(levelFile);
  startAttempt();
}

// A fresh try at the current level: player back at the spawn, music from the top.
// A play-test started part-way (testStart) restarts from that point instead, with the
// level clock and the music moved on to when a run from the spawn would get there.
void startAttempt() {
  resetPlayer();
  float from = 0;
  if (testing && testStart != null) {
    player = new Player(testStart);
    // the run speed is constant, so distance along x is time
    from = max(0, (testStart.x - level.spawn.x) / player.runSpeed);
    level.fastForward(from);
    cam = camTarget();
  }
  state = PLAYING;
  music.start(level.music, from);
}

void pauseGame() {
  state = PAUSED;
  music.pause();
}

void resumeGame() {
  state = PLAYING;
  music.resume();
}

// Back to the level list to pick the next one. Does not save: the editor asks about
// unsaved changes before calling this. A new level that was never saved has no file.
void exitEditor() {
  if (levelExists(levelFile)) {
    level = new Level(levelFile);
    resetPlayer();
  }
  openLevelSelect(true);
}

void keyReleased() {
  keybinds.released();
  if (state == EDITOR) editor.keyReleased();
}

void mousePressed() {
  if (state == EDITOR) editor.mousePressed();
  else if (state == SETTINGS && mouseButton == LEFT) {
    if (settingsMenu.mousePressed()) state = settingsMenu.returnState;
  }
  else if (state == LEVEL_SELECT && mouseButton == LEFT) {
    String file = levelSelect.mousePressed();
    if (file != null) chooseLevel(file);
  }
  else if (mouseButton != LEFT) return;
  else if (testing && overStopButton()) stopTest();  // works on the death screen too
  else if (state == MAIN_MENU) chooseMain(mainMenu.mousePressed());
  else if (state == PAUSED) choosePause(pauseMenu.mousePressed());
  else if (state == WON) chooseWin(winMenu.mousePressed());
  else if (state == DEAD) chooseDeath(deathMenu.mousePressed());
  else if (state == PLAYING) player.jump();  // same as space
}

void mouseDragged() {
  if (state == EDITOR) editor.mouseDragged();
  else if (state == SETTINGS) settingsMenu.mouseDragged();
}

void mouseReleased() {
  if (state == EDITOR) editor.mouseReleased();
  else if (state == SETTINGS) settingsMenu.mouseReleased();
}

void mouseWheel(MouseEvent event) {
  if (state == EDITOR) editor.mouseWheel(event.getCount());
}

// An orthographic view looking at target: turned by yaw around y, then tilted down
// by pitch, at s screen pixels per world unit. The target sits at the screen centre.
class OrthoView {
  PVector target;
  float yaw, pitch, s;

  OrthoView(PVector target, float yaw, float pitch, float s) {
    this.target = target;
    this.yaw = yaw;
    this.pitch = pitch;
    this.s = s;
  }

  // Sets up the world transform. Afterwards you draw in world units with y up.
  void apply() {
    translate(width / 2, height / 2, 0);
    scale(s, -s, s);   // world units to pixels, and flip y so +y is up
    rotateX(pitch);    // tilt to look down on the tops
    rotateY(yaw);      // swing around the vertical axis
    translate(-target.x, -target.y, -target.z);
  }

  // World direction to view space (x right, y up, z toward the camera), as apply() does
  PVector rotate(PVector p) {
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    float rx = p.x * cy + p.z * sy;
    float rz = -p.x * sy + p.z * cy;
    return new PVector(rx, p.y * cp - rz * sp, p.y * sp + rz * cp);
  }

  // View space back to a world direction
  PVector unrotate(PVector e) {
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    float ry = e.y * cp + e.z * sp;
    float rz = -e.y * sp + e.z * cp;
    return new PVector(e.x * cy - rz * sy, ry, e.x * sy + rz * cy);
  }

  // Screen pixel position of a world point
  PVector toScreen(PVector p) {
    PVector e = rotate(PVector.sub(p, target));
    return new PVector(width / 2 + e.x * s, height / 2 - e.y * s);
  }

  // The world point under a screen pixel, on the plane through target facing the camera
  PVector fromScreen(float sx, float sy) {
    PVector e = new PVector((sx - width / 2) / s, -(sy - height / 2) / s, 0);
    return PVector.add(target, unrotate(e));
  }

  // World-space direction from the scene toward the camera
  PVector eye() {
    return unrotate(new PVector(0, 0, 1));
  }
}

// The game camera. t: 0 = side view, 1 = iso.
// The view shift is a real camera rotation: yaw around y, then tilt down.
OrthoView gameView(float t) {
  return new OrthoView(cam, ISO_YAW * t, ISO_PITCH * t, screenScale(t));
}

void applyCamera(float t) {
  gameView(t).apply();
}

// Screen pixels per world unit at view blend t
float screenScale(float t) {
  return worldUnits * lerp(1, ISO_ZOOM, t);
}

// World-space direction from the scene toward the game camera at view blend t
PVector towardCamera(float t) {
  return gameView(t).eye();
}
