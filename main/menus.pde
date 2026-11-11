// A vertical list of options navigated with W/S or the arrow keys, Enter to choose.
class Menu {
  String title;
  String[] items;
  int selected = 0;

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

  // Drawn in screen space (call outside the camera translate)
  void display() {
    // dim whatever is behind the menu
    noStroke();
    fill(0, 150);
    rect(0, 0, width, height);

    textAlign(CENTER, CENTER);
    fill(255);
    textSize(48);
    text(title, width / 2, height * 0.3);

    textSize(28);
    for (int i = 0; i < items.length; i++) {
      float y = height * 0.45 + i * 50;
      if (i == selected) {
        fill(255, 200, 60);
        text(items[i], width / 2, y);
      } else {
        fill(200);
        text(items[i], width / 2, y);
      }
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

class MainMenu extends Menu {
  MainMenu() {
    super("Ephemeral Dash", new String[] { "Play", "Settings", "Level Creator", "Quit" });
  }
}

// Level select: a line of numbered boxes, one per level file (level1.json, level2.json, ...).
// At least MIN_LEVELS boxes are shown, more if higher-numbered files exist. In play
// mode only levels that exist can be chosen. In edit mode an empty slot starts a new
// level there, and an extra "+" box at the end makes the next level number.
// When the line is wider than the window it pages sideways.
final int MIN_LEVELS = 5;
final float LS_BOX = 120, LS_GAP = 30, LS_MARGIN = 40;  // pixels

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

  boolean overArrow(int dir) {
    return hasPage(dir) && abs(mouseX - arrowX(dir)) < LS_MARGIN / 2
        && abs(mouseY - (boxY() + LS_BOX / 2)) < LS_BOX / 2;
  }

  void display() {
    noStroke();
    fill(0, 150);
    rect(0, 0, width, height);

    textAlign(CENTER, CENTER);
    fill(255);
    textSize(48);
    text(editMode ? "Edit Level" : "Select Level", width / 2, height * 0.25);

    int hover = boxAt(mouseX, mouseY);
    if (hover >= 0 && usable(hover)) selected = hover;  // the mouse moves the highlight too

    for (int i = firstOnPage(); i < firstOnPage() + countOnPage(); i++) {
      float x = boxX(i), y = boxY();
      boolean on = i == selected;
      boolean can = usable(i);

      fill(can ? (on ? color(255, 200, 60, 60) : color(255, 20)) : color(255, 6));
      stroke(on ? color(255, 200, 60) : can ? color(200) : color(90));
      strokeWeight(on ? 3 : 2);
      rect(x, y, LS_BOX, LS_BOX, 10);

      fill(on ? color(255, 200, 60) : can ? color(255) : color(90));
      textSize(56);
      text(isAddBox(i) ? "+" : str(i + 1), x + LS_BOX / 2, y + LS_BOX / 2 - 6);
    }

    // page arrows, and which page this is
    textSize(40);
    for (int dir = -1; dir <= 1; dir += 2) {
      if (!hasPage(dir)) continue;
      fill(overArrow(dir) ? color(255, 200, 60) : color(200));
      text(dir < 0 ? "<" : ">", arrowX(dir), boxY() + LS_BOX / 2 - 4);
    }
    if (pageCount() > 1) {
      textSize(16);
      fill(150);
      text((page() + 1) + " / " + pageCount(), width / 2, boxY() + LS_BOX + 30);
    }

    textSize(16);
    fill(150);
    String action = editMode ? "edit" : "play";
    text("A/D or arrows to choose, Enter or click to " + action + ", Esc to go back", width / 2, height * 0.75);
  }
}
