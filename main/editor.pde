import java.util.HashSet;

// Level creator. The level is edited as a grid of unit cells; on save, cells of the
// same block type are merged into as few boxes as possible (greedy meshing) and written
// in the normal level format.
//
// The editor draws the level in 3D with a free orbiting camera. Picking casts a ray
// from the mouse into the grid; handles and markers are drawn as 2D overlays.

final float HANDLE_RADIUS = 7;  // pixels
final float MIN_ZOOM = 0.25, MAX_ZOOM = 4;
final float DRAG_THRESHOLD = 4;  // pixels a right-press must move before it pans instead of removing
final float ROTATE_SPEED = 2;    // Q/E turn speed, radians per second
final float ORBIT_SPEED = 0.01;  // middle-drag turn, radians per pixel
final float MAX_PITCH = radians(89);  // stop just short of straight up or down

class Editor {
  String file;
  String name;
  PVector spawn, goal;

  CellGrid grid = new CellGrid();
  Cell selected;
  int brush = BLOCK_PLATFORM;

  boolean isIso = true;
  float t = 1;  // view blend, same meaning as Player.shiftT: side view flattens yaw and pitch
  PVector cam;  // world point at the screen centre
  float yaw = ISO_YAW, pitch = ISO_PITCH;
  float zoom = 1;
  boolean dragging, dragMoved;
  int dragButton;
  float dragStartX, dragStartY, lastDragX, lastDragY;
  boolean panLeft, panRight, panUp, panDown, rotLeft, rotRight, viewKeyDown;

  String message = "";
  int messageUntil = 0;

  Editor(String file) {
    this.file = file;
    load();
    cam = spawn.copy();
  }

  OrthoView view() {
    return new OrthoView(cam, yaw * t, pitch * t, screenScale(t) * zoom);
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

  // handles and picking (mouse positions are screen pixels)

  PVector handleWorld(Cell c, int[] d) {
    return new PVector(c.x + 0.5 + d[0] * 0.9, c.y + 0.5 + d[1] * 0.9, c.z + 0.5 + d[2] * 0.9);
  }

  PVector cellCenter(Cell c) {
    return new PVector(c.x + 0.5, c.y + 0.5, c.z + 0.5);
  }

  // Covered faces get no handle, and neither do ones pointing (nearly) straight at
  // the camera, which would sit right on top of the cube
  boolean handleUsable(Cell c, int[] d, PVector eye) {
    if (grid.get(c.x + d[0], c.y + d[1], c.z + d[2]) != null) return false;
    return abs(dirDot(d, eye)) < 0.95;
  }

  // Faces on the far side of the cube
  boolean handleFacesAway(int[] d, PVector eye) {
    return dirDot(d, eye) < -0.05;
  }

  int handleAt(float sx, float sy) {
    if (selected == null) return -1;
    OrthoView v = view();
    PVector eye = v.eye();
    for (int i = 0; i < DIRS.length; i++) {
      if (!handleUsable(selected, DIRS[i], eye)) continue;
      PVector s = v.toScreen(handleWorld(selected, DIRS[i]));
      if (dist(sx, sy, s.x, s.y) <= HANDLE_RADIUS + 3) return i;
    }
    return -1;
  }

  // Nearest cell under the mouse: a ray from the camera through the pixel
  Cell cellAt(float sx, float sy) {
    OrthoView v = view();
    PVector eye = v.eye();
    PVector o = PVector.add(v.fromScreen(sx, sy), PVector.mult(eye, 10000));
    PVector d = PVector.mult(eye, -1);
    Cell best = null;
    float bestS = Float.MAX_VALUE;
    for (Cell c : grid.cells.values()) {
      float s = rayEntry(o, d, c.minB(), c.maxB());
      if (s >= 0 && s < bestS) {
        bestS = s;
        best = c;
      }
    }
    return best;
  }

  void removeCell(Cell c) {
    if (c == null) return;
    grid.remove(c);
    if (selected == c) selected = null;
  }

  // camera

  // Moves the view by screen pixels
  void panPixels(float dx, float dy) {
    cam = view().fromScreen(width / 2 + dx, height / 2 + dy);
  }

  // Zooms by a factor, keeping the point under (sx, sy) fixed on screen
  void zoomAt(float factor, float sx, float sy) {
    PVector before = view().fromScreen(sx, sy);
    zoom = constrain(zoom * factor, MIN_ZOOM, MAX_ZOOM);
    cam.add(PVector.sub(before, view().fromScreen(sx, sy)));
  }

  // Turning only makes sense in the iso view (side view flattens the angles away)
  void orbit(float dYaw, float dPitch) {
    isIso = true;
    yaw += dYaw;
    pitch = constrain(pitch + dPitch, -MAX_PITCH, MAX_PITCH);
  }

  // update / draw

  void update(float dt) {
    float speed = 600 * dt;  // screen pixels per second
    float dx = 0, dy = 0;
    if (panLeft) dx -= speed;
    if (panRight) dx += speed;
    if (panUp) dy -= speed;
    if (panDown) dy += speed;
    if (dx != 0 || dy != 0) panPixels(dx, dy);

    if (rotLeft) orbit(-ROTATE_SPEED * dt, 0);
    if (rotRight) orbit(ROTATE_SPEED * dt, 0);

    float target = isIso ? 1 : 0;
    t += (target - t) * min(1, dt * 15);
  }

  void display() {
    OrthoView v = view();
    PVector eye = v.eye();
    int hover = handleAt(mouseX, mouseY);

    // the level, in world space
    hint(ENABLE_DEPTH_TEST);
    pushMatrix();
    v.apply();
    noLights();
    noStroke();
    beginShape(QUADS);
    for (Cell c : grid.cells.values()) {
      if (c.type != BLOCK_DOT) grid.cellFaces(c, 255, eye);
    }
    endShape();
    for (Cell c : grid.cells.values()) {
      if (c.type == BLOCK_DOT) drawBall(cellCenter(c), DOT_RADIUS, color(255, 200, 60));
    }

    // preview of the cell a hovered handle would add (translucent, so it writes no depth)
    if (hover >= 0) {
      int[] d = DIRS[hover];
      int px = selected.x + d[0], py = selected.y + d[1], pz = selected.z + d[2];
      hint(DISABLE_DEPTH_MASK);
      if (brush == BLOCK_DOT) {
        drawBall(new PVector(px + 0.5, py + 0.5, pz + 0.5), DOT_RADIUS, color(255, 200, 60, 110));
      } else {
        noLights();
        noStroke();
        beginShape(QUADS);
        grid.cellFaces(px, py, pz, brush, 110, eye);
        endShape();
      }
      hint(ENABLE_DEPTH_MASK);
    }
    popMatrix();

    // screen-space overlays
    noLights();
    hint(DISABLE_DEPTH_TEST);
    if (selected != null) drawOutline(selected, v);
    drawMarker(spawn, color(255, 80, 80), v);
    drawMarker(goal, color(80, 220, 120), v);
    if (selected != null) drawHandles(hover, v);
    drawHud();
  }

  // Outlines the faces of a cell's box that face the camera
  void drawOutline(Cell c, OrthoView v) {
    PVector mn = c.minB(), mx = c.maxB(), eye = v.eye();
    noFill();
    stroke(255, 200, 60);
    strokeWeight(2);
    for (int[] d : DIRS) {
      if (dirDot(d, eye) <= 0.001) continue;
      beginShape();
      for (float[] p : grid.faceCorners(0, 0, 0, d)) {  // unit face, stretched to the box
        PVector s = v.toScreen(new PVector(lerp(mn.x, mx.x, p[0]), lerp(mn.y, mx.y, p[1]), lerp(mn.z, mx.z, p[2])));
        vertex(s.x, s.y);
      }
      endShape(CLOSE);
    }
  }

  void drawHandles(int hover, OrthoView v) {
    PVector eye = v.eye();
    PVector center = v.toScreen(cellCenter(selected));
    for (int i = 0; i < DIRS.length; i++) {
      int[] d = DIRS[i];
      if (!handleUsable(selected, d, eye)) continue;

      PVector s = v.toScreen(handleWorld(selected, d));
      float a = handleFacesAway(d, eye) ? 110 : 255;  // far-side handles are faded but still clickable
      stroke(255, a);
      strokeWeight(2);
      line(center.x, center.y, s.x, s.y);
      fill(i == hover ? color(255, 200, 60, a) : color(255, a));
      circle(s.x, s.y, HANDLE_RADIUS * 2 * (i == hover ? 1.3 : 1));
    }
  }

  void drawMarker(PVector p, color c, OrthoView v) {
    PVector s = v.toScreen(new PVector(p.x, p.y + 0.5, p.z));
    noFill();
    stroke(c);
    strokeWeight(2);
    circle(s.x, s.y, v.s);
  }

  void drawHud() {
    noStroke();
    fill(255);
    textAlign(LEFT, TOP);
    textSize(16);
    text("Level Creator - " + file, 12, 12);
    text("Brush: " + BLOCK_NAMES[brush] + "   [1] Platform  [2] Cube  [3] Dot", 12, 34);
    text("Left click: select, or click a handle to add   Right click / Delete: remove", 12, 56);
    text("WASD / right drag: pan   Wheel: zoom   Q/E / middle drag: rotate   R: switch view", 12, 78);
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
    // Right drag pans and middle drag orbits. A right click that never moves removes on release.
    if (mouseButton == RIGHT || mouseButton == CENTER) {
      dragging = true;
      dragButton = mouseButton;
      dragMoved = mouseButton == CENTER;
      dragStartX = lastDragX = mouseX;
      dragStartY = lastDragY = mouseY;
      return;
    }

    if (mouseButton == LEFT) {
      int h = handleAt(mouseX, mouseY);
      if (h >= 0) {
        int[] d = DIRS[h];
        selected = grid.put(selected.x + d[0], selected.y + d[1], selected.z + d[2], brush);
        return;
      }
      if (grid.isEmpty()) {
        // nothing to build from yet: start under the spawn point
        selected = grid.put(floor(spawn.x), floor(spawn.y) - 1, floor(spawn.z), brush);
        return;
      }
      selected = cellAt(mouseX, mouseY);
    }
  }

  void mouseDragged() {
    if (!dragging) return;
    if (dist(mouseX, mouseY, dragStartX, dragStartY) > DRAG_THRESHOLD) dragMoved = true;
    if (dragMoved) {
      float dx = mouseX - lastDragX, dy = mouseY - lastDragY;
      if (dragButton == CENTER) orbit(dx * ORBIT_SPEED, dy * ORBIT_SPEED);
      else panPixels(-dx, -dy);
    }
    lastDragX = mouseX;
    lastDragY = mouseY;
  }

  void mouseReleased() {
    if (!dragging) return;
    dragging = false;
    if (!dragMoved) {  // only a right press can reach here unmoved; middle starts as moved
      removeCell(cellAt(dragStartX, dragStartY));
    }
  }

  void mouseWheel(float count) {
    zoomAt(pow(1.1, -count), mouseX, mouseY);
  }

  void keyPressed() {
    setKeys(key, true);

    if (key == '1') brush = BLOCK_PLATFORM;
    if (key == '2') brush = BLOCK_CUBE;
    if (key == '3') brush = BLOCK_DOT;

    if ((key == 'r' || key == 'R') && !viewKeyDown) {
      viewKeyDown = true;
      isIso = !isIso;
    }
    if ((key == DELETE || key == BACKSPACE) && selected != null) removeCell(selected);
    if (key == ENTER || key == RETURN) save();
  }

  void keyReleased() {
    setKeys(key, false);
    if (key == 'r' || key == 'R') viewKeyDown = false;
  }

  void setKeys(char k, boolean down) {
    switch (Character.toLowerCase(k)) {
      case 'a': panLeft = down; break;
      case 'd': panRight = down; break;
      case 'w': panUp = down; break;
      case 's': panDown = down; break;
      case 'q': rotLeft = down; break;
      case 'e': rotRight = down; break;
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
