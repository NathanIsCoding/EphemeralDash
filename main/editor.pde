import java.util.HashSet;

// Level creator. The level is edited as a grid of unit cells; on save, cells of the
// same block type are merged into as few boxes as possible (greedy meshing) and written
// in the normal level format.
//
// The view can be turned in 90 degree steps. Rather than moving the camera, the editor
// keeps a second, display-only grid with every cell's x/z rotated, and draws, sorts and
// picks on that. Edits go to the real grid and the display grid is rebuilt.

// The six face directions of a cell
final int[][] DIRS = {
  { -1, 0, 0 }, { 1, 0, 0 },
  { 0, 1, 0 }, { 0, -1, 0 },
  { 0, 0, 1 }, { 0, 0, -1 }
};

final float HANDLE_RADIUS = 7;  // pixels
final float MIN_ZOOM = 0.25, MAX_ZOOM = 4;
final float DRAG_THRESHOLD = 4;  // pixels a right-press must move before it pans instead of removing

class Editor {
  String file;
  String name;
  PVector spawn, goal;

  CellGrid grid = new CellGrid();  // the real level, in world coordinates
  CellGrid view;                   // the same cells rotated for display; never edited directly
  int rot = 0;                     // quarter turns, 0..3
  Cell selected;                   // a cell of the real grid
  int brush = BLOCK_PLATFORM;

  boolean isIso = true;
  float t = 1;  // view blend, same meaning as Player.shiftT
  PVector cam;      // view centre, in unscaled world pixels
  float zoom = 1;
  boolean dragging, dragMoved;
  float dragStartX, dragStartY, lastDragX, lastDragY;
  boolean panLeft, panRight, panUp, panDown, viewKeyDown, rotKeyDown;

  String message = "";
  int messageUntil = 0;

  Editor(String file) {
    this.file = file;
    load();
    rebuildView();
    cam = worldToScreen(spawn.x, spawn.y, spawn.z, t);
  }

  // rotation 

  // One quarter turn maps the point (x, z) to (-z, x). A unit cell's corner moves
  // by an extra -1 on x, because the cell's far corner becomes its near one.
  int[] toViewCell(int x, int z) {
    for (int i = 0; i < rot; i++) {
      int nx = -z - 1;
      z = x;
      x = nx;
    }
    return new int[] { x, z };
  }

  int[] toWorldCell(int x, int z) {
    for (int i = 0; i < rot; i++) {
      int nx = z;
      z = -x - 1;
      x = nx;
    }
    return new int[] { x, z };
  }

  PVector toViewPoint(PVector p) {
    float x = p.x, z = p.z;
    for (int i = 0; i < rot; i++) {
      float nx = -z;
      z = x;
      x = nx;
    }
    return new PVector(x, p.y, z);
  }

  void rebuildView() {
    view = new CellGrid();
    for (Cell c : grid.cells.values()) {
      int[] v = toViewCell(c.x, c.z);
      view.put(v[0], c.y, v[1], c.type);
    }
  }

  // The display cell for a real cell, and back
  Cell viewOf(Cell c) {
    if (c == null) return null;
    int[] v = toViewCell(c.x, c.z);
    return view.get(v[0], c.y, v[1]);
  }

  Cell worldOf(Cell v) {
    if (v == null) return null;
    int[] w = toWorldCell(v.x, v.z);
    return grid.get(w[0], v.y, w[1]);
  }

  // Turns the view, keeping the selected cell (or the spawn) at the same place on screen
  void rotate(int steps) {
    PVector before = pivotScreen();
    rot = (rot + steps + 4) % 4;
    rebuildView();
    cam.add(PVector.sub(pivotScreen(), before));
  }

  PVector pivotScreen() {
    if (selected != null) return view.screenCenter(viewOf(selected), t);
    PVector s = toViewPoint(spawn);
    return worldToScreen(s.x, s.y, s.z, t);
  }

  // load / save 

  void load() {
    JSONObject json = loadJSONObject("levels/" + file);
    name = json.getString("name", file);
    spawn = readVec(json.getJSONArray("spawn"));
    goal = readVec(json.getJSONArray("goal"));
    grid.addBoxes(json.getJSONArray("platforms"), BLOCK_PLATFORM);
    grid.addBoxes(json.getJSONArray("cubes"), BLOCK_CUBE);
    grid.addDots(json.getJSONArray("dots"));
  }

  void save() {
    JSONArray ds = new JSONArray();
    for (Cell c : sortedCells()) {
      if (c.type != BLOCK_DOT) continue;
      JSONObject d = new JSONObject();
      d.setJSONArray("pos", intsJSON(c.x, c.y, c.z));
      d.setFloat("radius", DOT_RADIUS);
      ds.append(d);
    }

    // save data to JSON
    ArrayList<String> out = new ArrayList<String>();
    out.add("{");
    out.add("  \"name\": " + compactJSON(name) + ",");
    out.add("  \"spawn\": " + compactJSON(vecJSON(spawn)) + ",");
    out.add("  \"goal\": " + compactJSON(vecJSON(goal)) + ",");
    addJSONList(out, "platforms", mergeBoxes(BLOCK_PLATFORM), true);
    addJSONList(out, "cubes", mergeBoxes(BLOCK_CUBE), true);
    addJSONList(out, "dots", ds, false);
    out.add("}");

    saveStrings(dataPath("levels/" + file), out.toArray(new String[0]));
    flash("Saved " + file);
  }

  // Writes "key": [ ... ] with one item per line
  void addJSONList(ArrayList<String> out, String key, JSONArray items, boolean trailingComma) {
    String end = trailingComma ? "," : "";
    if (items.size() == 0) {
      out.add("  \"" + key + "\": []" + end);
      return;
    }
    out.add("  \"" + key + "\": [");
    for (int i = 0; i < items.size(); i++) {
      out.add("    " + compactJSON(items.get(i)) + (i < items.size() - 1 ? "," : ""));
    }
    out.add("  ]" + end);
  }

  // Cells ordered by y, then z, then x, so the first unused cell of a box is its min corner
  ArrayList<Cell> sortedCells() {
    ArrayList<Cell> list = new ArrayList<Cell>(grid.cells.values());
    list.sort((a, b) -> {
      if (a.y != b.y) return Integer.compare(a.y, b.y);
      if (a.z != b.z) return Integer.compare(a.z, b.z);
      return Integer.compare(a.x, b.x);
    });
    return list;
  }

  // Greedy meshing: grow each box along x, then z, then y while every cell it would
  // cover is the same type and not already in another box
  JSONArray mergeBoxes(int type) {
    JSONArray out = new JSONArray();
    HashSet<String> used = new HashSet<String>();

    for (Cell c : sortedCells()) {
      if (c.type != type || used.contains(grid.keyOf(c.x, c.y, c.z))) continue;

      int w = 1, d = 1, h = 1;
      while (boxFree(c.x + w, c.y, c.z, 1, 1, 1, type, used)) w++;
      while (boxFree(c.x, c.y, c.z + d, w, 1, 1, type, used)) d++;
      while (boxFree(c.x, c.y + h, c.z, w, 1, d, type, used)) h++;

      for (int x = 0; x < w; x++)
        for (int y = 0; y < h; y++)
          for (int z = 0; z < d; z++)
            used.add(grid.keyOf(c.x + x, c.y + y, c.z + z));

      JSONObject b = new JSONObject();
      b.setJSONArray("pos", intsJSON(c.x, c.y, c.z));
      b.setJSONArray("size", intsJSON(w, h, d));
      out.append(b);
    }
    return out;
  }

  // true if every cell in the w*h*d block starting at (x, y, z) is the given type and unused
  boolean boxFree(int x0, int y0, int z0, int w, int h, int d, int type, HashSet<String> used) {
    for (int x = x0; x < x0 + w; x++)
      for (int y = y0; y < y0 + h; y++)
        for (int z = z0; z < z0 + d; z++) {
          Cell c = grid.get(x, y, z);
          if (c == null || c.type != type || used.contains(grid.keyOf(x, y, z))) return false;
        }
    return true;
  }

  // handles and picking (all in display coordinates)

  PVector handlePos(Cell c, int[] d) {
    return worldToScreen(c.x + 0.5 + d[0] * 0.9, c.y + 0.5 + d[1] * 0.9, c.z + 0.5 + d[2] * 0.9, t);
  }

  // Covered faces get no handle; depth handles are hidden in side view, where they
  // would sit right on top of the cube
  boolean handleUsable(Cell c, int[] d) {
    if (view.get(c.x + d[0], c.y + d[1], c.z + d[2]) != null) return false;
    if (d[2] != 0 && t < 0.5) return false;
    return true;
  }

  // Faces on the far side of the cube (+x, -z, bottom), only meaningful in iso
  boolean handleFacesAway(int[] d) {
    return t >= 0.5 && (d[0] == 1 || d[2] == -1 || d[1] == -1);
  }

  int handleAt(float mx, float my) {
    Cell sel = viewOf(selected);
    if (sel == null) return -1;
    for (int i = 0; i < DIRS.length; i++) {
      if (!handleUsable(sel, DIRS[i])) continue;
      PVector s = handlePos(sel, DIRS[i]);
      if (dist(mx, my, s.x, s.y) <= (HANDLE_RADIUS + 3) / zoom) return i;
    }
    return -1;
  }

  // Front-most display cell under the mouse, tested in reverse draw order
  Cell cellAt(float mx, float my) {
    ArrayList<Cell> o = view.drawOrder();
    for (int i = o.size() - 1; i >= 0; i--) {
      Cell c = o.get(i);
      if (c.type == BLOCK_DOT) {
        PVector s = view.screenCenter(c, t);
        if (dist(mx, my, s.x, s.y) <= DOT_RADIUS * screenScale(t)) return c;
        continue;
      }
      for (int f = 0; f < 3; f++) {
        if (view.faceVisible(c, f) && inQuad(mx, my, view.faceCorners(c.x, c.y, c.z, f, t))) return c;
      }
    }
    return null;
  }

  // Adds a block at the real cell that the display cell (vx, y, vz) shows
  Cell addAtView(int vx, int y, int vz) {
    int[] w = toWorldCell(vx, vz);
    Cell c = grid.put(w[0], y, w[1], brush);
    rebuildView();
    return c;
  }

  void removeCell(Cell c) {
    if (c == null) return;
    grid.remove(c);
    if (selected == c) selected = null;
    rebuildView();
  }

  // update / draw 

  // camera 

  // Screen position of the world origin. cam is scaled before rounding so the
  // view stays pixel-aligned at any zoom.
  float originX() { return width / 2 - round(cam.x * zoom); }
  float originY() { return height / 2 - round(cam.y * zoom); }

  // A screen position in the unscaled coordinates the level is drawn and picked in
  float localX(float sx) { return (sx - originX()) / zoom; }
  float localY(float sy) { return (sy - originY()) / zoom; }

  // Zooms by a factor, keeping the point under (sx, sy) fixed on screen
  void zoomAt(float factor, float sx, float sy) {
    float px = localX(sx), py = localY(sy);
    zoom = constrain(zoom * factor, MIN_ZOOM, MAX_ZOOM);
    cam.x = px - (sx - width / 2) / zoom;
    cam.y = py - (sy - height / 2) / zoom;
  }

  void update(float dt) {
    float speed = 600 * dt / zoom;  // same speed on screen at any zoom
    if (panLeft) cam.x -= speed;
    if (panRight) cam.x += speed;
    if (panUp) cam.y -= speed;
    if (panDown) cam.y += speed;

    float target = isIso ? 1 : 0;
    t += (target - t) * min(1, dt * 15);
  }

  void display() {
    pushMatrix();
    translate(originX(), originY());
    scale(zoom);

    Cell sel = viewOf(selected);
    for (Cell c : view.drawOrder()) view.drawCell(c, t, 255, c == sel);

    drawMarker(toViewPoint(spawn), color(255, 80, 80));
    drawMarker(toViewPoint(goal), color(80, 220, 120));

    if (selected != null) drawHandles();
    popMatrix();

    drawHud();
  }

  void drawHandles() {
    int hover = handleAt(localX(mouseX), localY(mouseY));
    Cell sel = viewOf(selected);

    // preview of the cell a hovered handle would add
    if (hover >= 0) {
      int[] d = DIRS[hover];
      view.drawCell(new Cell(sel.x + d[0], sel.y + d[1], sel.z + d[2], brush), t, 110, false);
    }

    PVector center = view.screenCenter(sel, t);
    for (int i = 0; i < DIRS.length; i++) {
      int[] d = DIRS[i];
      if (!handleUsable(sel, d)) continue;

      PVector s = handlePos(sel, d);
      float a = handleFacesAway(d) ? 110 : 255;  // far-side handles are faded but still clickable
      stroke(255, a);
      strokeWeight(2 / zoom);  // handles keep their size on screen at any zoom
      line(center.x, center.y, s.x, s.y);
      fill(i == hover ? color(255, 200, 60, a) : color(255, a));
      circle(s.x, s.y, HANDLE_RADIUS * 2 / zoom * (i == hover ? 1.3 : 1));
    }
  }

  void drawMarker(PVector p, color c) {
    PVector s = worldToScreen(p.x, p.y + 0.5, p.z, t);
    noFill();
    stroke(c);
    strokeWeight(2);
    circle(s.x, s.y, screenScale(t));
  }

  void drawHud() {
    noStroke();
    fill(255);
    textAlign(LEFT, TOP);
    textSize(16);
    text("Level Creator - " + file, 12, 12);
    text("Brush: " + BLOCK_NAMES[brush] + "   [1] Platform  [2] Cube  [3] Dot", 12, 34);
    text("Left click: select, or click a handle to add   Right click / Delete: remove", 12, 56);
    text("WASD / right or middle drag: pan   Wheel: zoom   Q/E: rotate   R: switch view", 12, 78);
    text("Enter: save   Esc: save and exit   Zoom: " + nf(zoom, 1, 2) + "x", 12, 100);
    if (millis() < messageUntil) {
      fill(255, 200, 60);
      text(message, 12, 126);
    }
  }

  void flash(String msg) {
    message = msg;
    messageUntil = millis() + 1500;
  }

  // input 

  void mousePressed() {
    float mx = localX(mouseX), my = localY(mouseY);

    // Right and middle start a drag. A right click that never moves removes on release.
    if (mouseButton == RIGHT || mouseButton == CENTER) {
      dragging = true;
      dragMoved = mouseButton == CENTER;
      dragStartX = lastDragX = mouseX;
      dragStartY = lastDragY = mouseY;
      return;
    }

    if (mouseButton == LEFT) {
      int h = handleAt(mx, my);
      if (h >= 0) {
        // handle directions are in display space, so step there and convert back
        Cell sel = viewOf(selected);
        int[] d = DIRS[h];
        selected = addAtView(sel.x + d[0], sel.y + d[1], sel.z + d[2]);
        return;
      }
      if (grid.isEmpty()) {
        // nothing to build from yet: start under the spawn point
        selected = grid.put(floor(spawn.x), floor(spawn.y) - 1, floor(spawn.z), brush);
        rebuildView();
        return;
      }
      selected = worldOf(cellAt(mx, my));
    }
  }

  void mouseDragged() {
    if (!dragging) return;
    if (dist(mouseX, mouseY, dragStartX, dragStartY) > DRAG_THRESHOLD) dragMoved = true;
    if (dragMoved) {
      cam.x -= (mouseX - lastDragX) / zoom;
      cam.y -= (mouseY - lastDragY) / zoom;
    }
    lastDragX = mouseX;
    lastDragY = mouseY;
  }

  void mouseReleased() {
    if (!dragging) return;
    dragging = false;
    if (!dragMoved) {  // only a right press can reach here unmoved; middle starts as moved
      removeCell(worldOf(cellAt(localX(dragStartX), localY(dragStartY))));
    }
  }

  void mouseWheel(float count) {
    zoomAt(pow(1.1, -count), mouseX, mouseY);
  }

  void keyPressed() {
    setPan(key, true);

    if (key == '1') brush = BLOCK_PLATFORM;
    if (key == '2') brush = BLOCK_CUBE;
    if (key == '3') brush = BLOCK_DOT;

    if ((key == 'r' || key == 'R') && !viewKeyDown) {
      viewKeyDown = true;
      isIso = !isIso;
    }
    boolean q = key == 'q' || key == 'Q', e = key == 'e' || key == 'E';
    if ((q || e) && !rotKeyDown) {
      rotKeyDown = true;
      rotate(q ? -1 : 1);
    }
    if ((key == DELETE || key == BACKSPACE) && selected != null) removeCell(selected);
    if (key == ENTER || key == RETURN) save();
  }

  void keyReleased() {
    setPan(key, false);
    if (key == 'r' || key == 'R') viewKeyDown = false;
    if ("qQeE".indexOf(key) >= 0) rotKeyDown = false;
  }

  void setPan(char k, boolean down) {
    switch (Character.toLowerCase(k)) {
      case 'a': panLeft = down; break;
      case 'd': panRight = down; break;
      case 'w': panUp = down; break;
      case 's': panDown = down; break;
    }
  }
}

JSONArray vecJSON(PVector v) {
  JSONArray a = new JSONArray();
  a.append(v.x);
  a.append(v.y);
  a.append(v.z);
  return a;
}

// Single-line JSON for a value. Object keys are sorted so output is stable (pos before size/radius).
String compactJSON(Object v) {
  if (v instanceof JSONObject) {
    JSONObject o = (JSONObject) v;
    ArrayList<String> keys = new ArrayList<String>();
    for (Object k : o.keys()) keys.add((String) k);
    java.util.Collections.sort(keys);
    StringBuilder sb = new StringBuilder("{");
    for (int i = 0; i < keys.size(); i++) {
      if (i > 0) sb.append(", ");
      sb.append(compactJSON(keys.get(i))).append(": ").append(compactJSON(o.get(keys.get(i))));
    }
    return sb.append("}").toString();
  }
  if (v instanceof JSONArray) {
    JSONArray a = (JSONArray) v;
    StringBuilder sb = new StringBuilder("[");
    for (int i = 0; i < a.size(); i++) {
      if (i > 0) sb.append(", ");
      sb.append(compactJSON(a.get(i)));
    }
    return sb.append("]").toString();
  }
  if (v instanceof String) {
    return "\"" + ((String) v).replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
  }
  if (v instanceof Number) {
    double d = ((Number) v).doubleValue();
    if (d == Math.rint(d)) return String.valueOf((long) d);
    return String.valueOf((float) d);
  }
  return String.valueOf(v);
}

JSONArray intsJSON(int x, int y, int z) {
  JSONArray a = new JSONArray();
  a.append(x);
  a.append(y);
  a.append(z);
  return a;
}
