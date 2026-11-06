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
final int EDITOR = 3;
int state = MAIN_MENU;

String levelFile = "level1.json";
Editor editor;

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
  level = new Level(levelFile);
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
  level.display(player, state == PLAYING ? dt : 0);
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

void mouseDragged() {
  if (state == EDITOR) editor.mouseDragged();
}

void mouseReleased() {
  if (state == EDITOR) editor.mouseReleased();
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
