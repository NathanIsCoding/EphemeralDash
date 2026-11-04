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
    super("Paused", new String[] { "Resume", "Settings", "Main Menu", "Quit" });
  }
}
