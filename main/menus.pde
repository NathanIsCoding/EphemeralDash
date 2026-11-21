// Shared menu style, set by the main menu: dark panels, flat grey buttons, and the
// highlighted button filled with the accent colour (dark text on it).
final float MM_BTN_H = 58, MM_BTN_GAP = 16;  // button height and spacing, pixels
final float MM_BTN_GROW = 24;                // extra width of the highlighted button
final color MM_PANEL = #26262B, MM_BTN = #3A3A41, MM_ACCENT = #FFC83C;
final color MM_TEXT = #E1E1E1, MM_TEXT_ON = #1E1E1E;  // button text, normal and highlighted
final color MM_MUTED = #9A9AA2;                       // headings and hints
final float MENU_DIM = 120;  // how much the world behind a menu is darkened (0..255)

// A flat button-shaped bar; the caller draws its contents
void drawMenuBar(float x, float y, float w, float h, boolean on) {
  noStroke();
  fill(on ? MM_ACCENT : MM_BTN);
  rect(x, y, w, h, 4);
}

color menuTextColor(boolean on) {
  return on ? MM_TEXT_ON : MM_TEXT;
}

// A vertical list of options navigated with W/S or the arrow keys, Enter to choose.
// Drawn like the main menu: a dark panel down the left edge with the title and a
// stack of buttons, and whatever is behind the menu (dimmed) to its right.
class Menu {
  String title;
  String[] items;
  int selected = 0;
  color titleColor = #FFFFFF;

  Menu(String title, String[] items) {
    this.title = title;
    this.items = items;
  }

  // Returns the chosen item when Enter is pressed, otherwise null
  String keyPressed() {
    boolean up = (key == CODED && keyCode == UP) || key == 'w' || key == 'W';
    boolean down = (key == CODED && keyCode == DOWN) || key == 's' || key == 'S';

    if (up) selected = (selected - 1 + items.length) % items.length;
    if (down) selected = (selected + 1) % items.length;
    if (key == ENTER || key == RETURN) return items[selected];
    return null;
  }

  // Returns the clicked item, or null
  String mousePressed() {
    int i = itemAt(mouseX, mouseY);
    if (i < 0) return null;
    selected = i;
    return items[i];
  }

  float panelWidth() {
    return constrain(width * 0.3, 340, 520);
  }

  float buttonWidth() {
    return panelWidth() - 120;
  }

  float itemY(int i) {
    return height * 0.45 + i * (MM_BTN_H + MM_BTN_GAP);
  }

  // Index of the button under the mouse, or -1. The hit area is the highlighted (wider) size.
  int itemAt(float mx, float my) {
    float cx = panelWidth() / 2, halfW = (buttonWidth() + MM_BTN_GROW) / 2;
    for (int i = 0; i < items.length; i++) {
      if (abs(mx - cx) < halfW && abs(my - itemY(i)) < MM_BTN_H / 2) return i;
    }
    return -1;
  }

  // Hovering moves the highlight, but only when the mouse moves, so a resting
  // mouse does not fight the keyboard (or grab the highlight the moment a menu opens)
  void trackHover() {
    if (mouseX == pmouseX && mouseY == pmouseY) return;
    int i = itemAt(mouseX, mouseY);
    if (i >= 0) selected = i;
  }

  // What shows right of the panel: the world, dimmed
  void drawBackdrop(float pw) {
    noStroke();
    fill(0, MENU_DIM);
    rect(pw, 0, width - pw, height);
  }

  void drawTitle(float pw, float cx) {
    fill(titleColor);
    textSize(min(64, pw / 6.5));
    text(title.toUpperCase(), cx, height * 0.22);
  }

  // Drawn in screen space (call outside the camera translate)
  void display() {
    float pw = panelWidth(), cx = pw / 2;
    drawBackdrop(pw);

    noStroke();
    fill(MM_PANEL);
    rect(0, 0, pw, height);

    textAlign(CENTER, CENTER);
    drawTitle(pw, cx);

    trackHover();
    textSize(26);
    for (int i = 0; i < items.length; i++) {
      boolean on = i == selected;
      float bw = buttonWidth() + (on ? MM_BTN_GROW : 0);
      float y = itemY(i);
      drawMenuBar(cx - bw / 2, y - MM_BTN_H / 2, bw, MM_BTN_H, on);
      fill(menuTextColor(on));
      text(items[i].toUpperCase(), cx, y - 2);
    }
  }
}

class PauseMenu extends Menu {
  PauseMenu() {
    super("Paused", new String[] { "Resume", "Level Select", "Settings", "Main Menu", "Quit" });
  }
}

// Shown when the player reaches the goal. "Next Level" is only offered when the
// next level file exists.
class WinMenu extends Menu {
  String nextFile;  // null on the last level

  WinMenu() {
    super("You Win!", new String[] { "Level Select" });
  }

  void open(String file) {
    String[] m = match(file, "^level([0-9]+)[.]json$");
    nextFile = null;
    if (m != null) {
      String next = levelFileFor(Integer.parseInt(m[1]) + 1);
      if (levelExists(next)) nextFile = next;
    }
    items = nextFile != null ? new String[] { "Next Level", "Level Select" } : new String[] { "Level Select" };
    selected = 0;
  }
}

// Shown when the player dies, with a red title. It stays until the player picks an option.
class DeathMenu extends Menu {
  DeathMenu() {
    super("You Died", new String[] { "Retry", "Level Select" });
    titleColor = #FF5050;
  }

  // A play-test from the editor goes back there instead of to the level select
  void open(boolean testing) {
    items = new String[] { "Retry", testing ? "Back to Editor" : "Level Select" };
    selected = 0;
  }
}

// The main menu: the shared menu panel, with the title on two lines and the music
// visualizer filling the rest of the screen to its right.
class MainMenu extends Menu {
  MainMenu() {
    super("Ephemeral Dash", new String[] { "Play", "Settings", "Level Creator", "Quit" });
  }

  void drawBackdrop(float pw) {
    drawVisualizer(pw, width);
  }

  // one word per line
  void drawTitle(float pw, float cx) {
    fill(titleColor);
    textSize(min(64, pw / 6.5));
    text("EPHEMERAL", cx, height * 0.17);
    textSize(min(84, pw / 4.5));
    text("DASH", cx, height * 0.17 + min(80, pw / 5));
  }
}

// Level select: a line of numbered boxes, one per level file (level1.json, level2.json, ...).
// At least MIN_LEVELS boxes are shown, more if higher-numbered files exist. In play
// mode only levels that exist can be chosen. In edit mode an empty slot starts a new
// level there, and an extra "+" box at the end makes the next level number.
// When the line is wider than the window it pages sideways.
final int MIN_LEVELS = 5;
final float LS_BOX = 120, LS_GAP = 30, LS_MARGIN = 40;  // pixels
final float LS_BACK_X = 24, LS_BACK_Y = 24, LS_BACK_W = 150, LS_BACK_H = 48;  // the back button

String levelFileFor(int n) {
  return "level" + n + ".json";
}

boolean levelExists(String file) {
  return new File(dataPath("levels/" + file)).exists();
}

// Highest n with a levelN.json in data/levels, or 0
int highestLevel() {
  String[] files = new File(dataPath("levels")).list();
  int best = 0;
  if (files == null) return best;
  for (String f : files) {
    String[] m = match(f, "^level([0-9]+)[.]json$");
    if (m != null) best = max(best, Integer.parseInt(m[1]));
  }
  return best;
}

class LevelSelect {
  boolean editMode;
  int selected = 0;      // 0-based box index; box i is level i + 1
  boolean[] exists = new boolean[0];
  int slots;             // numbered boxes; edit mode adds the "+" box after them

  // Re-reads which levels exist, since the editor may have just made one
  void open(boolean editMode) {
    this.editMode = editMode;
    slots = max(MIN_LEVELS, highestLevel());
    exists = new boolean[slots];
    for (int i = 0; i < slots; i++) exists[i] = levelExists(levelFileFor(i + 1));
    if (selected >= boxCount() || !usable(selected)) selected = firstUsable();
  }

  int boxCount() {
    return editMode ? slots + 1 : slots;
  }

  boolean isAddBox(int i) {
    return editMode && i == slots;
  }

  boolean usable(int i) {
    return editMode || exists[i];
  }

  int firstUsable() {
    for (int i = 0; i < boxCount(); i++) if (usable(i)) return i;
    return 0;
  }

  // Moves the selection by dir, skipping boxes that cannot be chosen (no wrap-around)
  void step(int dir) {
    for (int i = selected + dir; i >= 0 && i < boxCount(); i += dir) {
      if (usable(i)) {
        selected = i;
        return;
      }
    }
  }

  // Returns the chosen level file, or null
  String keyPressed() {
    boolean left = (key == CODED && keyCode == LEFT) || key == 'a' || key == 'A';
    boolean right = (key == CODED && keyCode == RIGHT) || key == 'd' || key == 'D';
    if (left) step(-1);
    if (right) step(1);
    if ((key == ENTER || key == RETURN) && usable(selected)) return levelFileFor(selected + 1);
    return null;
  }

  // Returns the clicked level file, or null. Clicking an arrow turns the page.
  String mousePressed() {
    if (overArrow(-1)) { turnPage(-1); return null; }
    if (overArrow(1)) { turnPage(1); return null; }
    int i = boxAt(mouseX, mouseY);
    if (i < 0 || !usable(i)) return null;
    selected = i;
    return levelFileFor(i + 1);
  }

  // paging

  int perPage() {
    return max(1, floor((width - 2 * LS_MARGIN + LS_GAP) / (LS_BOX + LS_GAP)));
  }

  int page() {
    return selected / perPage();
  }

  int pageCount() {
    return (boxCount() + perPage() - 1) / perPage();
  }

  void turnPage(int dir) {
    int p = constrain(page() + dir, 0, pageCount() - 1);
    if (p == page()) return;
    selected = p * perPage();
    if (!usable(selected)) step(1);
  }

  // layout

  int firstOnPage() {
    return page() * perPage();
  }

  int countOnPage() {
    return min(perPage(), boxCount() - firstOnPage());
  }

  float boxX(int i) {
    int n = countOnPage();
    float total = n * LS_BOX + (n - 1) * LS_GAP;
    return (width - total) / 2 + (i - firstOnPage()) * (LS_BOX + LS_GAP);
  }

  float boxY() {
    return height * 0.45 - LS_BOX / 2;
  }

  int boxAt(float mx, float my) {
    for (int i = firstOnPage(); i < firstOnPage() + countOnPage(); i++) {
      if (mx >= boxX(i) && mx < boxX(i) + LS_BOX && my >= boxY() && my < boxY() + LS_BOX) return i;
    }
    return -1;
  }

  boolean hasPage(int dir) {
    int p = page() + dir;
    return p >= 0 && p < pageCount();
  }

  // The page arrows sit just outside the line of boxes, at its middle height
  float arrowX(int dir) {
    return dir < 0 ? LS_MARGIN / 2 : width - LS_MARGIN / 2;
  }

  // The back button in the top-left corner; it does what Esc does
  boolean overBack() {
    return mouseX >= LS_BACK_X && mouseX < LS_BACK_X + LS_BACK_W
        && mouseY >= LS_BACK_Y && mouseY < LS_BACK_Y + LS_BACK_H;
  }

  void drawBack() {
    boolean on = overBack();
    drawMenuBar(LS_BACK_X, LS_BACK_Y, LS_BACK_W, LS_BACK_H, on);
    fill(menuTextColor(on));
    textSize(22);
    text("BACK", LS_BACK_X + LS_BACK_W / 2, LS_BACK_Y + LS_BACK_H / 2 - 2);
  }

  boolean overArrow(int dir) {
    return hasPage(dir) && abs(mouseX - arrowX(dir)) < LS_MARGIN / 2
        && abs(mouseY - (boxY() + LS_BOX / 2)) < LS_BOX / 2;
  }

  void display() {
    // in the main menu's style: its panel colour across the whole screen, the boxes
    // as its buttons (accent when highlighted), and levels that cannot be chosen
    // drawn faintly
    noStroke();
    fill(MM_PANEL);
    rect(0, 0, width, height);

    textAlign(CENTER, CENTER);
    fill(255);
    textSize(56);
    text(editMode ? "EDIT LEVEL" : "SELECT LEVEL", width / 2, height * 0.25);
    drawBack();

    int hover = boxAt(mouseX, mouseY);
    if (hover >= 0 && usable(hover)) selected = hover;  // the mouse moves the highlight too

    for (int i = firstOnPage(); i < firstOnPage() + countOnPage(); i++) {
      float x = boxX(i), y = boxY();
      boolean on = i == selected;
      boolean can = usable(i);

      if (can) {
        drawMenuBar(x, y, LS_BOX, LS_BOX, on);
        fill(menuTextColor(on));
      } else {
        fill(MM_BTN, 90);
        rect(x, y, LS_BOX, LS_BOX, 4);
        fill(MM_TEXT, 45);
      }
      textSize(56);
      text(isAddBox(i) ? "+" : str(i + 1), x + LS_BOX / 2, y + LS_BOX / 2 - 6);
    }

    // page arrows, and which page this is
    textSize(40);
    for (int dir = -1; dir <= 1; dir += 2) {
      if (!hasPage(dir)) continue;
      fill(overArrow(dir) ? MM_ACCENT : MM_TEXT);
      text(dir < 0 ? "<" : ">", arrowX(dir), boxY() + LS_BOX / 2 - 4);
    }
    if (pageCount() > 1) {
      textSize(16);
      fill(MM_MUTED);
      text((page() + 1) + " / " + pageCount(), width / 2, boxY() + LS_BOX + 30);
    }

    textSize(16);
    fill(MM_MUTED);
    String action = editMode ? "edit" : "play";
    text("A/D or arrows to choose, Enter or click to " + action + ", Esc to go back", width / 2, height * 0.75);
  }
}
