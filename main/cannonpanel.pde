// Editor window for the timing of the targeted cannons, shown in the bottom-left (above the timeline) while
// any are selected. Each row has a slider and a box you can click and type a value into:
//   Interval: seconds between shots
//   Delay:    the offset, so cannons with the same interval can fire out of step
// Changes apply to every targeted cannon at once.

final float CP_W = 320, CP_PAD = 12, CP_TITLE_H = 22, CP_ROW = 34;
final float CP_LABEL_W = 64, CP_SLIDER_W = 150, CP_BOX_W = 58, CP_BOX_H = 24;
final float INTERVAL_MIN = 0.25;        // seconds
final float INTERVAL_SLIDER_MAX = 6;    // the slider's range; typing allows up to INTERVAL_MAX
final float INTERVAL_MAX = 60;
final float SLIDER_SNAP = 0.05;         // slider values land on multiples of this

final int CP_INTERVAL = 0, CP_DELAY = 1;
final String[] CP_LABELS = { "Interval", "Delay" };

class CannonPanel {
  int dragging = -1;  // row whose slider is being dragged
  int editing = -1;   // row whose text box is being typed in
  String typed = "";

  // layout

  float x() { return TB_X; }
  float h() { return CP_PAD * 2 + CP_TITLE_H + CP_LABELS.length * CP_ROW; }
  float y() { return height - TB_Y - TL_H - TL_GAP - h(); }  // above the timeline
  float rowMid(int r) { return y() + CP_PAD + CP_TITLE_H + r * CP_ROW + CP_ROW / 2; }
  float sliderX() { return x() + CP_PAD + CP_LABEL_W; }
  float boxX() { return sliderX() + CP_SLIDER_W + 16; }

  boolean over(float mx, float my) {
    return mx >= x() && mx < x() + CP_W && my >= y() && my < y() + h();
  }

  boolean overSlider(int r, float mx, float my) {
    return mx >= sliderX() - 8 && mx < sliderX() + CP_SLIDER_W + 8 && abs(my - rowMid(r)) < CP_ROW / 2;
  }

  boolean overBox(int r, float mx, float my) {
    return mx >= boxX() && mx < boxX() + CP_BOX_W && abs(my - rowMid(r)) < CP_BOX_H / 2;
  }

  // values. The first cannon stands in for the group on the sliders.

  float value(int r, Cell c) {
    return r == CP_INTERVAL ? c.interval : c.offset;
  }

  float lo(int r) {
    return r == CP_INTERVAL ? INTERVAL_MIN : 0;
  }

  // Delay runs up to one interval: any more only shifts the pattern by a whole shot
  float hi(int r, Cell c) {
    return r == CP_INTERVAL ? INTERVAL_SLIDER_MAX : c.interval;
  }

  boolean mixed(int r, ArrayList<Cell> cs) {
    for (Cell c : cs) if (abs(value(r, c) - value(r, cs.get(0))) > 0.001) return true;
    return false;
  }

  void apply(int r, float v, ArrayList<Cell> cs) {
    for (Cell c : cs) {
      if (r == CP_INTERVAL) c.interval = constrain(v, INTERVAL_MIN, INTERVAL_MAX);
      else c.offset = v;
      c.offset = constrain(c.offset, 0, c.interval);  // a shorter interval pulls the delay in with it
    }
  }

  void slideTo(int r, float mx, ArrayList<Cell> cs) {
    float t = constrain((mx - sliderX()) / CP_SLIDER_W, 0, 1);
    float v = lerp(lo(r), hi(r, cs.get(0)), t);
    apply(r, round(v / SLIDER_SNAP) * SLIDER_SNAP, cs);
  }

  // Applies the typed text, if it is a number, and stops editing
  void commit(ArrayList<Cell> cs) {
    if (editing < 0) return;
    try {
      if (!cs.isEmpty()) apply(editing, Float.parseFloat(typed), cs);
    } catch (NumberFormatException e) {
      // not a number: keep the old value
    }
    editing = -1;
  }

  void cancel() {
    editing = -1;
  }

  // input (the editor only calls these while cannons are targeted)

  void mousePressed(ArrayList<Cell> cs) {
    for (int r = 0; r < CP_LABELS.length; r++) {
      if (overBox(r, mouseX, mouseY)) {
        if (editing == r) return;  // already typing here
        commit(cs);
        editing = r;
        typed = mixed(r, cs) ? "" : fmt(value(r, cs.get(0)));
        return;
      }
    }
    commit(cs);
    for (int r = 0; r < CP_LABELS.length; r++) {
      if (overSlider(r, mouseX, mouseY)) {
        dragging = r;
        slideTo(r, mouseX, cs);
        return;
      }
    }
  }

  void mouseDragged(ArrayList<Cell> cs) {
    if (dragging >= 0 && !cs.isEmpty()) slideTo(dragging, mouseX, cs);
  }

  // Every key goes here while a box is being typed in, so none of them reach the editor
  void keyPressed(ArrayList<Cell> cs) {
    if (key == ENTER || key == RETURN) commit(cs);
    else if (key == TAB) {
      // Tab moves on to the other box
      int next = (editing + 1) % CP_LABELS.length;
      commit(cs);
      if (cs.isEmpty()) return;
      editing = next;
      typed = mixed(next, cs) ? "" : fmt(value(next, cs.get(0)));
    }
    else if (key == BACKSPACE) {
      if (typed.length() > 0) typed = typed.substring(0, typed.length() - 1);
    }
    else if (((key >= '0' && key <= '9') || (key == '.' && typed.indexOf('.') < 0)) && typed.length() < 6) {
      typed += key;
    }
  }

  String fmt(float v) {
    return nf(v, 1, 2);
  }

  void display(ArrayList<Cell> cs) {
    noStroke();
    fill(0, 190);
    rect(x(), y(), CP_W, h(), 8);

    textAlign(LEFT, CENTER);
    textSize(14);
    fill(255);
    text(cs.size() == 1 ? "Cannon timing" : "Cannon timing (" + cs.size() + " cannons)",
         x() + CP_PAD, y() + CP_PAD + CP_TITLE_H / 2 - 2);

    Cell first = cs.get(0);
    textSize(13);
    for (int r = 0; r < CP_LABELS.length; r++) {
      float my = rowMid(r);
      boolean hot = dragging == r || (dragging < 0 && overSlider(r, mouseX, mouseY));

      fill(200);
      text(CP_LABELS[r], x() + CP_PAD, my);

      // track, with the part up to the value filled in
      float t = constrain(norm(value(r, first), lo(r), hi(r, first)), 0, 1);
      float kx = sliderX() + t * CP_SLIDER_W;
      strokeWeight(4);
      stroke(255, 50);
      line(sliderX(), my, sliderX() + CP_SLIDER_W, my);
      stroke(255, 200, 60);
      line(sliderX(), my, kx, my);
      noStroke();
      fill(hot ? color(255, 220, 120) : color(255, 200, 60));
      circle(kx, my, hot ? 16 : 13);

      // text box
      boolean typing = editing == r;
      fill(typing ? color(255, 30) : color(255, 12));
      stroke(typing ? color(255, 200, 60) : overBox(r, mouseX, mouseY) ? color(200) : color(255, 60));
      strokeWeight(typing ? 2 : 1);
      rect(boxX(), my - CP_BOX_H / 2, CP_BOX_W, CP_BOX_H, 4);

      noStroke();
      String shown;
      if (typing) shown = typed + (millis() / 500 % 2 == 0 ? "|" : "");
      else shown = mixed(r, cs) ? "mixed" : fmt(value(r, first));
      fill(typing || !mixed(r, cs) ? color(255) : color(150));
      text(shown, boxX() + 7, my - 1);
      fill(170);
      text("s", boxX() + CP_BOX_W + 6, my - 1);
    }
  }
}
