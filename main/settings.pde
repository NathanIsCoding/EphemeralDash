// Rebindable gameplay keys, saved to data/settings.json.
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
    save();
  }

  void resetDefaults() {
    keys = DEFAULT_KEYS.clone();
    save();
  }

  void load() {
    File f = new File(dataPath(SETTINGS_FILE));
    if (!f.exists()) return;
    try {
      JSONObject binds = loadJSONObject(f.getPath()).getJSONObject("keybinds");
      if (binds == null) return;
      for (int i = 0; i < ACTION_NAMES.length; i++) {
        if (binds.hasKey(ACTION_NAMES[i])) keys[i] = binds.getInt(ACTION_NAMES[i]);
      }
    } catch (Exception e) {
      println("Could not read " + SETTINGS_FILE + ", using default keys: " + e);
    }
  }

  void save() {
    JSONObject binds = new JSONObject();
    for (int i = 0; i < ACTION_NAMES.length; i++) binds.setInt(ACTION_NAMES[i], keys[i]);
    JSONObject root = new JSONObject();
    root.setJSONObject("keybinds", binds);
    saveJSONObject(root, dataPath(SETTINGS_FILE));
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

// Settings screen: one row per action showing its key, then Reset and Back.
// Enter (or click) on a row waits for the next key and binds it; Esc cancels.
class SettingsMenu {
  int selected = 0;
  boolean listening = false;  // waiting for the new key for the selected action
  int returnState;            // where Back / Esc goes

  final float ROW_H = 50;

  void open(int from) {
    returnState = from;
    selected = 0;
    listening = false;
  }

  int rowCount() {
    return ACTION_NAMES.length + 2;  // actions, "Reset to Defaults", "Back"
  }

  float rowY(int i) {
    // a little gap between the key rows and the buttons
    return height * 0.3 + i * ROW_H + (i >= ACTION_NAMES.length ? 30 : 0);
  }

  int rowAt(float my) {
    for (int i = 0; i < rowCount(); i++) if (abs(my - rowY(i)) < ROW_H / 2) return i;
    return -1;
  }

  // Returns true when the menu wants to close
  boolean keyPressed() {
    if (listening) {
      listening = false;
      if (key != ESC) keybinds.bind(selected, keybinds.current());
      return false;
    }
    if (key == ESC) return true;

    boolean up = (key == CODED && keyCode == UP) || key == 'w' || key == 'W';
    boolean down = (key == CODED && keyCode == DOWN) || key == 's' || key == 'S';
    if (up) selected = (selected - 1 + rowCount()) % rowCount();
    if (down) selected = (selected + 1) % rowCount();
    if (key == ENTER || key == RETURN) return choose();
    return false;
  }

  boolean mousePressed() {
    if (listening) return false;
    int i = rowAt(mouseY);
    if (i < 0) return false;
    selected = i;
    return choose();
  }

  boolean choose() {
    if (selected < ACTION_NAMES.length) listening = true;
    else if (selected == ACTION_NAMES.length) keybinds.resetDefaults();
    else return true;  // Back
    return false;
  }

  void display() {
    noStroke();
    fill(0, 150);
    rect(0, 0, width, height);

    if (!listening) {
      int hover = rowAt(mouseY);
      if (hover >= 0) selected = hover;
    }

    textAlign(CENTER, CENTER);
    fill(255);
    textSize(48);
    text("Settings", width / 2, height * 0.15);

    textSize(20);
    fill(150);
    text("Keybinds", width / 2, height * 0.22);

    textSize(28);
    for (int i = 0; i < rowCount(); i++) {
      float y = rowY(i);
      boolean on = i == selected;
      fill(on ? color(255, 200, 60) : color(200));

      if (i < ACTION_NAMES.length) {
        textAlign(RIGHT, CENTER);
        text(ACTION_NAMES[i], width / 2 - 20, y);
        textAlign(LEFT, CENTER);
        String k = on && listening ? "Press a key..." : keybinds.nameOf(i);
        text("[ " + k + " ]", width / 2 + 20, y);
      } else {
        textAlign(CENTER, CENTER);
        text(i == ACTION_NAMES.length ? "Reset to Defaults" : "Back", width / 2, y);
      }
    }

    textAlign(CENTER, CENTER);
    textSize(16);
    fill(150);
    text(listening ? "Press the new key, or Esc to cancel" : "W/S or arrows to choose, Enter or click to rebind, Esc to go back", width / 2, height * 0.85);
  }
}
