// Player settings, saved to data/settings.json: the music volume and the gameplay keys.
//
// A key is stored as one int: a typed character is its lowercase char code, and a
// special key (arrows, shift, ...) is its negative keyCode. The negative keeps them
// apart, since e.g. UP's keyCode (38) is the same number as the '&' character.
final int ACT_JUMP = 0;
final int ACT_SHIFT = 1;
final int ACT_LANE_LEFT = 2;
final int ACT_LANE_RIGHT = 3;

final String[] ACTION_NAMES = { "Jump", "Shift View", "Lane Left", "Lane Right" };
final int[] DEFAULT_KEYS = { ' ', 'r', 'a', 'd' };

final String SETTINGS_FILE = "settings.json";
final float DEFAULT_VOLUME = 0.8;
final float VOLUME_STEP = 0.05;  // per A/D or arrow press

float musicVolume = DEFAULT_VOLUME;  // 0..1

// Call after keybinds and music exist
void loadSettings() {
  File f = new File(dataPath(SETTINGS_FILE));
  if (f.exists()) {
    try {
      JSONObject root = loadJSONObject(f.getPath());
      keybinds.fromJSON(root.getJSONObject("keybinds"));
      musicVolume = constrain(root.getFloat("musicVolume", DEFAULT_VOLUME), 0, 1);
    } catch (Exception e) {
      println("Could not read " + SETTINGS_FILE + ", using defaults: " + e);
    }
  }
  applyVolumes();
}

// How loud the menu music is next to the level music (0..1): it sits in the background
final float MENU_MUSIC_LEVEL = 0.1;

// The one volume setting covers the level music, the menu music and the win sound
void applyVolumes() {
  music.setVolume(musicVolume);
  menuMusic.setVolume(musicVolume * MENU_MUSIC_LEVEL);
  winSfx.setVolume(musicVolume);
}

void saveSettings() {
  JSONObject root = new JSONObject();
  root.setFloat("musicVolume", musicVolume);
  root.setJSONObject("keybinds", keybinds.toJSON());
  saveJSONObject(root, dataPath(SETTINGS_FILE));
}

void setMusicVolume(float v) {
  musicVolume = constrain(v, 0, 1);
  applyVolumes();
}

class Keybinds {
  int[] keys = DEFAULT_KEYS.clone();
  boolean[] down = new boolean[DEFAULT_KEYS.length];  // ignores key repeat, so holding only triggers once

  // The code for the key in the current key event
  int current() {
    return key == CODED ? -keyCode : Character.toLowerCase(key);
  }

  // The action bound to the current key, or -1
  int actionFor(int code) {
    for (int i = 0; i < keys.length; i++) if (keys[i] == code) return i;
    return -1;
  }

  // The action whose key was just pressed (not a repeat), or -1
  int pressed() {
    int a = actionFor(current());
    if (a < 0 || down[a]) return -1;
    down[a] = true;
    return a;
  }

  void released() {
    int a = actionFor(current());
    if (a >= 0) down[a] = false;
  }

  // Binds action to code. If another action already had that key, the two swap,
  // so every action always keeps a key.
  void bind(int action, int code) {
    int other = actionFor(code);
    if (other >= 0 && other != action) keys[other] = keys[action];
    keys[action] = code;
    saveSettings();
  }

  void resetDefaults() {
    keys = DEFAULT_KEYS.clone();
    saveSettings();
  }

  void fromJSON(JSONObject binds) {
    if (binds == null) return;
    for (int i = 0; i < ACTION_NAMES.length; i++) {
      if (binds.hasKey(ACTION_NAMES[i])) keys[i] = binds.getInt(ACTION_NAMES[i]);
    }
  }

  JSONObject toJSON() {
    JSONObject binds = new JSONObject();
    for (int i = 0; i < ACTION_NAMES.length; i++) binds.setInt(ACTION_NAMES[i], keys[i]);
    return binds;
  }

  String nameOf(int action) {
    return keyName(keys[action]);
  }
}

// Readable name for a stored key code
String keyName(int code) {
  if (code < 0) {
    switch (-code) {
      case UP: return "Up";
      case DOWN: return "Down";
      case LEFT: return "Left";
      case RIGHT: return "Right";
      case SHIFT: return "Shift";
      case CONTROL: return "Ctrl";
      case ALT: return "Alt";
      default: return "Key " + (-code);
    }
  }
  switch (code) {
    case ' ': return "Space";
    case ENTER: case RETURN: return "Enter";
    case TAB: return "Tab";
    case BACKSPACE: return "Backspace";
    case DELETE: return "Delete";
  }
  return str((char) code).toUpperCase();
}

// Settings screen. Rows, top to bottom:
//   0                 Music Volume (slider: drag or click it, or A/D / Left/Right)
//   1 .. actions      one per gameplay action; Enter or click waits for the new key, Esc cancels
//   then              "Reset Keybinds" and "Back"
final int SR_VOLUME = 0;
final int SR_FIRST_KEY = 1;
final float SLIDER_W = 160;
final float VOL_LABEL_GAP = 28, VOL_PCT_GAP = 16;  // label to bar, bar to percentage
final String VOL_LABEL = "Music Volume";

class SettingsMenu {
  int selected = 0;
  boolean listening = false;  // waiting for the new key for the selected action
  boolean dragging = false;   // dragging the volume slider
  int returnState;            // where Back / Esc goes

  final float ROW_H = 46;

  void open(int from) {
    returnState = from;
    selected = 0;
    listening = false;
    dragging = false;
  }

  int resetRow() { return SR_FIRST_KEY + ACTION_NAMES.length; }
  int backRow() { return resetRow() + 1; }
  int rowCount() { return backRow() + 1; }

  boolean isKeyRow(int i) { return i >= SR_FIRST_KEY && i < resetRow(); }

  // Each section has a heading above its rows, and the buttons sit a little apart
  float rowY(int i) {
    float y = height * 0.27;                        // the volume row, under "Audio"
    if (i >= SR_FIRST_KEY) y += 60 + 30;            // gap, "Keybinds" heading
    if (i >= SR_FIRST_KEY) y += (min(i, resetRow()) - SR_FIRST_KEY) * ROW_H;
    if (i >= resetRow()) y += 24 + (i - resetRow()) * ROW_H;
    return y;
  }

  float headingY(int firstRow) { return rowY(firstRow) - 44; }

  int rowAt(float my) {
    for (int i = 0; i < rowCount(); i++) if (abs(my - rowY(i)) < ROW_H / 2) return i;
    return -1;
  }

  // The volume row (label, bar, percentage) is centred as a whole, since its bar
  // makes it much wider on the right than the key rows
  float sliderX() {
    textSize(20);
    float pctW = textWidth("100%");  // widest value, so the row does not shift as it changes
    textSize(28);
    float labelW = textWidth(VOL_LABEL);
    float total = labelW + VOL_LABEL_GAP + SLIDER_W + VOL_PCT_GAP + pctW;
    return width / 2 - total / 2 + labelW + VOL_LABEL_GAP;
  }

  boolean overSlider(float mx, float my) {
    return mx >= sliderX() - 10 && mx < sliderX() + SLIDER_W + 10 && abs(my - rowY(SR_VOLUME)) < ROW_H / 2;
  }

  void slideTo(float mx) {
    float v = constrain((mx - sliderX()) / SLIDER_W, 0, 1);
    setMusicVolume(round(v * 100) / 100.0);
  }

  // Returns true when the menu wants to close
  boolean keyPressed() {
    if (listening) {
      listening = false;
      if (key != ESC) keybinds.bind(selected - SR_FIRST_KEY, keybinds.current());
      return false;
    }
    if (key == ESC) return true;

    boolean up = (key == CODED && keyCode == UP) || key == 'w' || key == 'W';
    boolean down = (key == CODED && keyCode == DOWN) || key == 's' || key == 'S';
    boolean left = (key == CODED && keyCode == LEFT) || key == 'a' || key == 'A';
    boolean right = (key == CODED && keyCode == RIGHT) || key == 'd' || key == 'D';
    if (up) selected = (selected - 1 + rowCount()) % rowCount();
    if (down) selected = (selected + 1) % rowCount();
    if (selected == SR_VOLUME && (left || right)) {
      setMusicVolume(round((musicVolume + (right ? VOLUME_STEP : -VOLUME_STEP)) * 100) / 100.0);
      saveSettings();
    }
    if (key == ENTER || key == RETURN) return choose();
    return false;
  }

  boolean mousePressed() {
    if (listening) return false;
    if (overSlider(mouseX, mouseY)) {
      selected = SR_VOLUME;
      dragging = true;
      slideTo(mouseX);
      return false;
    }
    int i = rowAt(mouseY);
    if (i < 0 || i == SR_VOLUME) return false;
    selected = i;
    return choose();
  }

  void mouseDragged() {
    if (dragging) slideTo(mouseX);
  }

  void mouseReleased() {
    if (!dragging) return;
    dragging = false;
    saveSettings();  // once per drag, not every frame of it
  }

  boolean choose() {
    if (isKeyRow(selected)) listening = true;
    else if (selected == resetRow()) keybinds.resetDefaults();
    else if (selected == backRow()) return true;
    return false;
  }

  void display() {
    noStroke();
    fill(0, 150);
    rect(0, 0, width, height);

    if (!listening && !dragging && (mouseX != pmouseX || mouseY != pmouseY)) {
      int hover = rowAt(mouseY);
      if (hover >= 0) selected = hover;
    }

    textAlign(CENTER, CENTER);
    fill(255);
    textSize(48);
    text("Settings", width / 2, height * 0.12);

    textSize(20);
    fill(150);
    text("Audio", width / 2, headingY(SR_VOLUME));
    text("Keybinds", width / 2, headingY(SR_FIRST_KEY));

    textSize(28);
    for (int i = 0; i < rowCount(); i++) {
      float y = rowY(i);
      boolean on = i == selected;
      color c = on ? color(255, 200, 60) : color(200);
      fill(c);

      if (i == SR_VOLUME) {
        float sx = sliderX();  // sets textSize(28) again for the label
        textAlign(RIGHT, CENTER);
        text(VOL_LABEL, sx - VOL_LABEL_GAP, y);
        drawVolumeSlider(y, on);
      } else if (isKeyRow(i)) {
        int a = i - SR_FIRST_KEY;
        textAlign(RIGHT, CENTER);
        text(ACTION_NAMES[a], width / 2 - 20, y);
        textAlign(LEFT, CENTER);
        String k = on && listening ? "Press a key..." : keybinds.nameOf(a);
        text("[ " + k + " ]", width / 2 + 20, y);
      } else {
        textAlign(CENTER, CENTER);
        text(i == resetRow() ? "Reset Keybinds" : "Back", width / 2, y);
      }
    }

    textAlign(CENTER, CENTER);
    textSize(16);
    fill(150);
    String hint;
    if (listening) hint = "Press the new key, or Esc to cancel";
    else if (selected == SR_VOLUME) hint = "A/D or Left/Right to adjust, or drag the slider. Esc to go back";
    else hint = "W/S or arrows to choose, Enter or click to rebind, Esc to go back";
    text(hint, width / 2, height * 0.9);
  }

  void drawVolumeSlider(float y, boolean on) {
    float x0 = sliderX(), kx = x0 + musicVolume * SLIDER_W;
    strokeWeight(6);
    stroke(255, 50);
    line(x0, y, x0 + SLIDER_W, y);
    stroke(on ? color(255, 200, 60) : color(200));
    if (musicVolume > 0) line(x0, y, kx, y);
    noStroke();
    fill(on ? color(255, 200, 60) : color(220));
    circle(kx, y, dragging ? 22 : 18);

    textAlign(LEFT, CENTER);
    textSize(20);
    fill(on ? color(255, 200, 60) : color(200));
    text(round(musicVolume * 100) + "%", x0 + SLIDER_W + VOL_PCT_GAP, y - 2);
    textSize(28);
  }
}
