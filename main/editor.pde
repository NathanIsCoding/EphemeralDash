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

// toolbar layout (pixels)
final float TB_X = 12, TB_Y = 12;
final float TB_BUTTON = 40, TB_GAP = 6, TB_SEP = 18, TB_PAD = 6;
// "|" is a separator between groups
final String[] TOOLS = { "build", "select", "fill", "|", "platform", "cube", "dot", "spike", "cannon", "|", "spawn", "goal", "|", "view", "save", "help", "exit" };
final String[] HELP_LINES = {
  "Build [B]: click a block, then a handle to add",
  "Select [V]: drag between blocks to box-select, Shift adds",
  "Fill [F]: drag across a block face to place a line or plane",
  "Spawn [P] / Goal [G]: click a block to place it on top",
  "T: turn the selected cannon(s) a quarter turn",
  "Right click / Delete: remove (the whole selection if any)",
  "WASD / right drag: pan",
  "Wheel: zoom",
  "Q/E / middle drag: rotate",
};

// Toolbar icon images in data/icons/ (Material Symbols, 24px), keyed by icon name.
// The brush icons stay procedural so they always match BLOCK_COLORS.
final String ICON_SIZE = "24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24";
final String[][] ICON_FILES = {
  { "build",     "add" },
  { "select",    "select" },
  { "fill",      "grid_4x4" },
  { "view_iso",  "deployed_code" },
  { "view_side", "square" },
  { "save",      "save" },
  { "help",      "help" },
  { "exit",      "logout" },
};
final float ICON_DRAW = 24;  // pixels; matches the images, so they are not resampled

final int TOOL_BUILD = 0, TOOL_SELECT = 1, TOOL_FILL = 2, TOOL_SPAWN = 3, TOOL_GOAL = 4;
final color SPAWN_COLOR = #FF5050, GOAL_COLOR = #50DC78;
final int MAX_FILL = 100;  // cells per side of one fill, so a slip of the mouse cannot place thousands

class Editor {
  String file;
  String name;
  PVector spawn, goal;

  CellGrid grid = new CellGrid();
  Cell selected;  // build tool: the cell whose handles are shown
  int brush = BLOCK_PLATFORM;
  int tool = TOOL_BUILD;

  // Multi-cell selection (select tool, and what the last fill placed)
  HashSet<Cell> selection = new HashSet<Cell>();
  boolean leftDragging;
  Cell selStart, selEnd;      // corners of the box being dragged out
  HashSet<Cell> selBase;      // selection before this drag, kept when Shift is held
  boolean shiftDown;

  // Fill tool: a rectangle of cells in the layer fillStart[fillAxis]
  boolean filling;
  int fillAxis;
  int[] fillStart, fillEnd;

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
  boolean showHelp = false;

  HashMap<String, PImage> icons = new HashMap<String, PImage>();

  Editor(String file) {
    this.file = file;
    for (String[] f : ICON_FILES) {
      icons.put(f[0], loadImage("icons/" + f[1] + "_" + ICON_SIZE + ".png"));
    }
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
    grid.addSpikes(json.getJSONArray("spikes"));
    grid.addCannons(json.getJSONArray("cannons"));
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
    JSONArray ss = new JSONArray();
    for (Cell c : sortedCells()) {
      if (c.type != BLOCK_SPIKE) continue;
      JSONObject s = new JSONObject();
      s.setJSONArray("pos", intsJSON(c.x, c.y, c.z));
      ss.append(s);
    }
    // cannons are saved one by one (never merged), since each has its own direction and timing
    JSONArray ns = new JSONArray();
    for (Cell c : sortedCells()) {
      if (c.type != BLOCK_CANNON) continue;
      JSONObject n = new JSONObject();
      n.setJSONArray("pos", intsJSON(c.x, c.y, c.z));
      n.setString("dir", DIR_NAMES[c.dir]);
      n.setFloat("interval", c.interval);
      n.setFloat("offset", c.offset);
      ns.append(n);
    }

    // save data to JSON
    ArrayList<String> out = new ArrayList<String>();
    out.add("{");
    out.add("  \"name\": " + compactJSON(name) + ",");
    out.add("  \"spawn\": " + compactJSON(vecJSON(spawn)) + ",");
    out.add("  \"goal\": " + compactJSON(vecJSON(goal)) + ",");
    addJSONList(out, "platforms", mergeBoxes(BLOCK_PLATFORM), true);
    addJSONList(out, "cubes", mergeBoxes(BLOCK_CUBE), true);
    addJSONList(out, "dots", ds, true);
    addJSONList(out, "spikes", ss, true);
    addJSONList(out, "cannons", ns, false);
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
    if (tool != TOOL_BUILD || selected == null) return -1;
    OrthoView v = view();
    PVector eye = v.eye();
    for (int i = 0; i < DIRS.length; i++) {
      if (!handleUsable(selected, DIRS[i], eye)) continue;
      PVector s = v.toScreen(handleWorld(selected, DIRS[i]));
      if (dist(sx, sy, s.x, s.y) <= HANDLE_RADIUS + 3) return i;
    }
    return -1;
  }

  // Ray from the camera through a screen pixel: { origin, direction }
  PVector[] mouseRay(float sx, float sy) {
    OrthoView v = view();
    PVector eye = v.eye();
    return new PVector[] { PVector.add(v.fromScreen(sx, sy), PVector.mult(eye, 10000)), PVector.mult(eye, -1) };
  }

  // Nearest cell under the mouse: a ray from the camera through the pixel
  Cell cellAt(float sx, float sy) {
    PVector[] r = mouseRay(sx, sy);
    Cell best = null;
    float bestS = Float.MAX_VALUE;
    for (Cell c : grid.cells.values()) {
      float s = rayEntry(r[0], r[1], c.minB(), c.maxB());
      if (s >= 0 && s < bestS) {
        bestS = s;
        best = c;
      }
    }
    return best;
  }

  // Index into DIRS of the face of c the mouse ray enters through
  int faceAt(Cell c, float sx, float sy) {
    PVector[] r = mouseRay(sx, sy);
    PVector mn = c.minB(), mx = c.maxB();
    PVector p = PVector.add(r[0], PVector.mult(r[1], rayEntry(r[0], r[1], mn, mx)));
    int best = 0;
    float bestGap = Float.MAX_VALUE;
    for (int i = 0; i < DIRS.length; i++) {
      int a = axisOf(DIRS[i]);
      float side = getAxis(DIRS[i][a] > 0 ? mx : mn, a);
      float gap = abs(getAxis(p, a) - side);
      if (gap < bestGap) {
        bestGap = gap;
        best = i;
      }
    }
    return best;
  }

  int axisOf(int[] d) {
    return d[0] != 0 ? 0 : d[1] != 0 ? 1 : 2;
  }

  void removeCell(Cell c) {
    if (c == null) return;
    grid.remove(c);
    selection.remove(c);
    if (selected == c) selected = null;
  }

  void removeSelection() {
    for (Cell c : selection) {
      grid.remove(c);
      if (selected == c) selected = null;
    }
    flash("Removed " + selection.size());
    selection.clear();
  }

  // Delete key / right click: the whole selection if there is one
  void removeAt(Cell c) {
    if (c != null && selection.contains(c)) removeSelection();
    else removeCell(c);
  }

  void setTool(int t) {
    tool = t;
    leftDragging = false;
    filling = false;
    if (t == TOOL_BUILD) selection.clear();  // build works on one cell at a time
  }

  // select tool

  void startSelect(float sx, float sy) {
    selBase = shiftDown ? new HashSet<Cell>(selection) : new HashSet<Cell>();
    selStart = selEnd = cellAt(sx, sy);
    updateSelection();
  }

  void dragSelect(float sx, float sy) {
    Cell c = cellAt(sx, sy);
    if (c == null) return;  // over empty space: keep the last corner
    if (selStart == null) selStart = c;
    selEnd = c;
    updateSelection();
  }

  // Selection = the base plus every cell inside the box spanned by the two corners
  void updateSelection() {
    selection = new HashSet<Cell>(selBase);
    if (selStart == null) return;
    int x0 = min(selStart.x, selEnd.x), x1 = max(selStart.x, selEnd.x);
    int y0 = min(selStart.y, selEnd.y), y1 = max(selStart.y, selEnd.y);
    int z0 = min(selStart.z, selEnd.z), z1 = max(selStart.z, selEnd.z);
    for (Cell c : grid.cells.values()) {
      if (c.x >= x0 && c.x <= x1 && c.y >= y0 && c.y <= y1 && c.z >= z0 && c.z <= z1) selection.add(c);
    }
  }

  // Turns every cannon in the selection (or the build tool's cell) a quarter turn
  void turnCannons() {
    ArrayList<Cell> targets = new ArrayList<Cell>(selection);
    if (targets.isEmpty() && selected != null) targets.add(selected);
    int turned = 0;
    for (Cell c : targets) {
      if (c.type != BLOCK_CANNON) continue;
      int i = 0;
      while (i < CANNON_DIRS.length && CANNON_DIRS[i] != c.dir) i++;
      c.dir = CANNON_DIRS[(i + 1) % CANNON_DIRS.length];  // an unknown dir starts over at -x
      turned++;
    }
    if (turned == 0) flash("Select a cannon to turn it");
  }

  // spawn / goal tools

  // Where a marker would go for a click at (sx, sy): standing on top of the block
  // under the mouse, in level coordinates (x, z at the cell centre, y = feet).
  // null if there is no block there, or the cell above it is taken.
  PVector markerSpot(float sx, float sy) {
    Cell c = cellAt(sx, sy);
    if (c == null || grid.get(c.x, c.y + 1, c.z) != null) return null;
    return new PVector(c.x + 0.5, c.y + 1, c.z + 0.5);
  }

  void placeMarker(float sx, float sy) {
    PVector p = markerSpot(sx, sy);
    if (p == null) {
      flash("Click the top of a block with free space above it");
      return;
    }
    if (tool == TOOL_SPAWN) spawn = p;
    else goal = p;
  }

  // fill tool

  // The fill grows in the layer just outside the clicked face. A face pointing
  // straight at the camera (as in side view) cannot be built out from, the same
  // as with handles, so then the fill stays in the clicked cell's own layer.
  void startFill(float sx, float sy) {
    Cell c = cellAt(sx, sy);
    if (c == null) return;
    int[] d = DIRS[faceAt(c, sx, sy)];
    boolean facing = abs(dirDot(d, view().eye())) >= 0.95;
    fillAxis = axisOf(d);
    fillStart = facing ? new int[] { c.x, c.y, c.z } : new int[] { c.x + d[0], c.y + d[1], c.z + d[2] };
    fillEnd = fillStart.clone();
    filling = true;
  }

  // The mouse ray meets the fill layer's mid-plane; the cell there is the far corner
  void dragFill(float sx, float sy) {
    PVector[] r = mouseRay(sx, sy);
    float da = getAxis(r[1], fillAxis);
    if (abs(da) < 0.05) return;  // looking along the layer edge-on: no sensible point
    float s = (fillStart[fillAxis] + 0.5 - getAxis(r[0], fillAxis)) / da;
    PVector p = PVector.add(r[0], PVector.mult(r[1], s));
    int[] e = { floor(p.x), floor(p.y), floor(p.z) };
    for (int a = 0; a < 3; a++) {
      if (a == fillAxis) e[a] = fillStart[a];
      else e[a] = constrain(e[a], fillStart[a] - (MAX_FILL - 1), fillStart[a] + (MAX_FILL - 1));
    }
    fillEnd = e;
  }

  // Empty cells in the fill rectangle (existing blocks are never overwritten)
  ArrayList<int[]> fillCells() {
    ArrayList<int[]> out = new ArrayList<int[]>();
    for (int x = min(fillStart[0], fillEnd[0]); x <= max(fillStart[0], fillEnd[0]); x++)
      for (int y = min(fillStart[1], fillEnd[1]); y <= max(fillStart[1], fillEnd[1]); y++)
        for (int z = min(fillStart[2], fillEnd[2]); z <= max(fillStart[2], fillEnd[2]); z++)
          if (grid.get(x, y, z) == null) out.add(new int[] { x, y, z });
    return out;
  }

  // Places the fill and selects it, so Delete takes it straight back out
  void finishFill() {
    filling = false;
    selection.clear();
    for (int[] p : fillCells()) selection.add(grid.put(p[0], p[1], p[2], brush));
    flash("Placed " + selection.size());
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

  // Turning only makes sense in the iso view (side view flattens the angles away).
  // OrthoView.apply() flips y (scale(s, -s, s)), which mirrors the handedness of
  // rotateY, so yaw is subtracted to make positive dYaw turn the view the intuitive way.
  // Yaw is kept in [-PI, PI): the view blend scales it toward 0, so a yaw wound up
  // over several turns would otherwise spin through all of them on the way to side view.
  void orbit(float dYaw, float dPitch) {
    isIso = true;
    yaw -= dYaw;
    yaw = ((yaw + PI) % TWO_PI + TWO_PI) % TWO_PI - PI;
    pitch = constrain(pitch + dPitch, -MAX_PITCH, MAX_PITCH);
  }

  // Switches between iso and side view. The view turns around cam, so first slide cam
  // along the view direction onto the block at the screen centre: the picture does
  // not move (the view is orthographic), but the turn now pivots on what you are looking at.
  void toggleView() {
    PVector[] r = mouseRay(width / 2, height / 2);
    float best = Float.MAX_VALUE;
    for (Cell c : grid.cells.values()) {
      float s = rayEntry(r[0], r[1], c.minB(), c.maxB());
      if (s >= 0 && s < best) best = s;
    }
    if (best < Float.MAX_VALUE) cam = PVector.add(r[0], PVector.mult(r[1], best));
    isIso = !isIso;
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
    int hover = overUI(mouseX, mouseY) ? -1 : handleAt(mouseX, mouseY);

    // the level, in world space
    hint(ENABLE_DEPTH_TEST);
    pushMatrix();
    v.apply();
    noLights();
    noStroke();
    beginShape(QUADS);
    for (Cell c : grid.cells.values()) {
      if (isBlock(c.type)) grid.cellFaces(c, 255, eye);
    }
    endShape();
    for (Cell c : grid.cells.values()) {
      if (c.type == BLOCK_DOT) drawBall(cellCenter(c), DOT_RADIUS, color(255, 200, 60));
      if (c.type == BLOCK_SPIKE) drawPyramid(c.x, c.y, c.z, SPIKE_HEIGHT, 255);
      if (c.type == BLOCK_CANNON) drawCannonBarrel(c.x, c.y, c.z, c.dir, 0);
    }

    // previews of what a click would add (translucent, so they write no depth)
    hint(DISABLE_DEPTH_MASK);
    if (hover >= 0) {
      int[] d = DIRS[hover];
      drawGhost(selected.x + d[0], selected.y + d[1], selected.z + d[2], eye);
    }
    if (filling) {
      for (int[] p : fillCells()) drawGhost(p[0], p[1], p[2], eye);
    }
    hint(ENABLE_DEPTH_MASK);
    popMatrix();

    // screen-space overlays
    noLights();
    hint(DISABLE_DEPTH_TEST);
    drawSelection(v);
    if (tool == TOOL_BUILD && selected != null) drawOutline(selected, v);
    drawMarker(spawn, SPAWN_COLOR, v);
    drawMarker(goal, GOAL_COLOR, v);
    if ((tool == TOOL_SPAWN || tool == TOOL_GOAL) && !overUI(mouseX, mouseY)) {
      PVector p = markerSpot(mouseX, mouseY);
      if (p != null) drawMarker(p, color(tool == TOOL_SPAWN ? SPAWN_COLOR : GOAL_COLOR, 110), v);
    }
    if (tool == TOOL_BUILD && selected != null) drawHandles(hover, v);
    drawHud();
  }

  // A translucent preview of a brush cell. Call in world space with the depth mask off.
  void drawGhost(int px, int py, int pz, PVector eye) {
    if (brush == BLOCK_DOT) {
      drawBall(new PVector(px + 0.5, py + 0.5, pz + 0.5), DOT_RADIUS, color(255, 200, 60, 110));
    } else if (brush == BLOCK_SPIKE) {
      drawPyramid(px, py, pz, SPIKE_HEIGHT, 110);
    } else {
      noLights();
      noStroke();
      beginShape(QUADS);
      grid.cellFaces(px, py, pz, brush, 110, eye);
      endShape();
    }
  }

  // Outlines the faces of a cell's box that face the camera
  void drawOutline(Cell c, OrthoView v) {
    PVector eye = v.eye();
    noFill();
    stroke(255, 200, 60);
    strokeWeight(2);
    for (int[] d : DIRS) {
      if (dirDot(d, eye) > 0.001) drawFaceOutline(c, d, v);
    }
  }

  // Outline of the selection as a whole: camera-facing faces of selected cells
  // whose neighbour on that side is not selected too
  void drawSelection(OrthoView v) {
    if (selection.isEmpty()) return;
    PVector eye = v.eye();
    noFill();
    stroke(80, 200, 255);
    strokeWeight(1.5);
    for (Cell c : selection) {
      for (int[] d : DIRS) {
        if (dirDot(d, eye) <= 0.001) continue;
        Cell n = grid.get(c.x + d[0], c.y + d[1], c.z + d[2]);
        if (n != null && selection.contains(n)) continue;
        drawFaceOutline(c, d, v);
      }
    }
  }

  void drawFaceOutline(Cell c, int[] d, OrthoView v) {
    PVector mn = c.minB(), mx = c.maxB();
    beginShape();
    for (float[] p : grid.faceCorners(0, 0, 0, d)) {  // unit face, stretched to the box
      PVector s = v.toScreen(new PVector(lerp(mn.x, mx.x, p[0]), lerp(mn.y, mx.y, p[1]), lerp(mn.z, mx.z, p[2])));
      vertex(s.x, s.y);
    }
    endShape(CLOSE);
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

  // toolbar

  // Left edge of each toolbar entry; separators get the TB_SEP width
  float[] toolXs() {
    float[] xs = new float[TOOLS.length];
    float x = TB_X + TB_PAD;
    for (int i = 0; i < TOOLS.length; i++) {
      xs[i] = x;
      x += (TOOLS[i].equals("|") ? TB_SEP : TB_BUTTON) + TB_GAP;
    }
    return xs;
  }

  float toolbarWidth() {
    float[] xs = toolXs();
    return xs[xs.length - 1] + TB_BUTTON + TB_PAD - TB_X;
  }

  float toolbarHeight() {
    return TB_BUTTON + TB_PAD * 2;
  }

  // Index into TOOLS of the button under the mouse, or -1
  int toolAt(float mx, float my) {
    float[] xs = toolXs();
    for (int i = 0; i < TOOLS.length; i++) {
      if (TOOLS[i].equals("|")) continue;
      if (inRect(mx, my, xs[i], TB_Y + TB_PAD, TB_BUTTON, TB_BUTTON)) return i;
    }
    return -1;
  }

  // true over the toolbar or the help panel, where clicks should not reach the level
  boolean overUI(float mx, float my) {
    if (inRect(mx, my, TB_X, TB_Y, toolbarWidth(), toolbarHeight())) return true;
    if (showHelp) {
      float[] r = helpRect();
      if (inRect(mx, my, r[0], r[1], r[2], r[3])) return true;
    }
    return false;
  }

  boolean inRect(float mx, float my, float x, float y, float w, float h) {
    return mx >= x && mx < x + w && my >= y && my < y + h;
  }

  void useTool(String id) {
    if (id.equals("build")) setTool(TOOL_BUILD);
    else if (id.equals("select")) setTool(TOOL_SELECT);
    else if (id.equals("fill")) setTool(TOOL_FILL);
    else if (id.equals("spawn")) setTool(TOOL_SPAWN);
    else if (id.equals("goal")) setTool(TOOL_GOAL);
    else if (id.equals("platform")) brush = BLOCK_PLATFORM;
    else if (id.equals("cube")) brush = BLOCK_CUBE;
    else if (id.equals("dot")) brush = BLOCK_DOT;
    else if (id.equals("spike")) brush = BLOCK_SPIKE;
    else if (id.equals("cannon")) brush = BLOCK_CANNON;
    else if (id.equals("view")) toggleView();
    else if (id.equals("save")) save();
    else if (id.equals("help")) showHelp = !showHelp;
    else if (id.equals("exit")) exitEditor();
  }

  boolean toolActive(String id) {
    if (id.equals("build")) return tool == TOOL_BUILD;
    if (id.equals("select")) return tool == TOOL_SELECT;
    if (id.equals("fill")) return tool == TOOL_FILL;
    if (id.equals("spawn")) return tool == TOOL_SPAWN;
    if (id.equals("goal")) return tool == TOOL_GOAL;
    if (id.equals("platform")) return brush == BLOCK_PLATFORM;
    if (id.equals("cube")) return brush == BLOCK_CUBE;
    if (id.equals("dot")) return brush == BLOCK_DOT;
    if (id.equals("spike")) return brush == BLOCK_SPIKE;
    if (id.equals("cannon")) return brush == BLOCK_CANNON;
    if (id.equals("help")) return showHelp;
    return false;
  }

  String toolTip(String id) {
    if (id.equals("build")) return "Build: click a block, then a handle  [B]";
    if (id.equals("select")) return "Select: drag a box, Shift adds  [V]";
    if (id.equals("fill")) return "Fill: drag a line or plane from a face  [F]";
    if (id.equals("spawn")) return "Place spawn on a block  [P]";
    if (id.equals("goal")) return "Place goal on a block  [G]";
    if (id.equals("platform")) return "Platform brush  [1]";
    if (id.equals("cube")) return "Cube brush  [2]";
    if (id.equals("dot")) return "Dot brush  [3]";
    if (id.equals("spike")) return "Spike brush  [4]";
    if (id.equals("cannon")) return "Cannon brush  [5]  (T turns it)";
    if (id.equals("view")) return (isIso ? "Switch to side view" : "Switch to iso view") + "  [R]";
    if (id.equals("save")) return "Save  [Enter]";
    if (id.equals("help")) return "Controls";
    if (id.equals("exit")) return "Save and exit  [Esc]";
    return "";
  }

  void drawHud() {
    float[] xs = toolXs();
    float by = TB_Y + TB_PAD;
    int hoverTool = toolAt(mouseX, mouseY);

    // bar background
    noStroke();
    fill(0, 160);
    rect(TB_X, TB_Y, toolbarWidth(), toolbarHeight(), 8);

    for (int i = 0; i < TOOLS.length; i++) {
      String id = TOOLS[i];
      if (id.equals("|")) {
        stroke(255, 60);
        strokeWeight(1);
        line(xs[i] + TB_SEP / 2, by + 6, xs[i] + TB_SEP / 2, by + TB_BUTTON - 6);
        continue;
      }
      boolean active = toolActive(id);
      noStroke();
      fill(active ? color(255, 200, 60, 70) : i == hoverTool ? color(255, 40) : color(255, 12));
      rect(xs[i], by, TB_BUTTON, TB_BUTTON, 6);
      if (active) {
        noFill();
        stroke(255, 200, 60);
        strokeWeight(2);
        rect(xs[i], by, TB_BUTTON, TB_BUTTON, 6);
      }
      drawToolIcon(id, xs[i] + TB_BUTTON / 2, by + TB_BUTTON / 2);
    }

    if (showHelp) drawHelp();
    if (hoverTool >= 0) drawTooltip(toolTip(TOOLS[hoverTool]), xs[hoverTool], TB_Y + toolbarHeight() + 8);
    if (millis() < messageUntil) {
      textSize(14);
      textAlign(LEFT, CENTER);
      fill(255, 200, 60);
      text(message, TB_X + toolbarWidth() + 12, TB_Y + toolbarHeight() / 2);
    }
  }

  void drawTooltip(String tip, float x, float y) {
    textSize(13);
    textAlign(LEFT, TOP);
    float w = textWidth(tip) + 16;
    noStroke();
    fill(0, 220);
    rect(x, y, w, 24, 5);
    fill(255);
    text(tip, x + 8, y + 5);
  }

  // x, y, w, h of the help panel, under the right end of the toolbar
  float[] helpRect() {
    float w = 420, h = HELP_LINES.length * 20 + 36;
    return new float[] { TB_X + toolbarWidth() - w, TB_Y + toolbarHeight() + 8, w, h };
  }

  void drawHelp() {
    float[] r = helpRect();
    noStroke();
    fill(0, 190);
    rect(r[0], r[1], r[2], r[3], 8);
    textAlign(LEFT, TOP);
    textSize(13);
    fill(255);
    for (int i = 0; i < HELP_LINES.length; i++) text(HELP_LINES[i], r[0] + 12, r[1] + 10 + i * 20);
    fill(170);
    text(file + "   zoom " + nf(zoom, 1, 2) + "x", r[0] + 12, r[1] + 14 + HELP_LINES.length * 20);
  }

  void drawToolIcon(String id, float cx, float cy) {
    if (id.equals("spawn") || id.equals("goal")) {
      // the same ring that marks it in the level
      noFill();
      stroke(id.equals("spawn") ? SPAWN_COLOR : GOAL_COLOR);
      strokeWeight(3);
      circle(cx, cy, 18);
    } else if (id.equals("platform")) {
      drawCubeIcon(cx, cy, 12, BLOCK_COLORS[BLOCK_PLATFORM]);
    } else if (id.equals("cube")) {
      drawCubeIcon(cx, cy, 12, BLOCK_COLORS[BLOCK_CUBE]);
    } else if (id.equals("dot")) {
      noStroke();
      fill(255, 200, 60);
      circle(cx, cy, 14);
    } else if (id.equals("cannon")) {
      // the firing face seen head-on: the muzzle above the lip
      noStroke();
      fill(BLOCK_COLORS[BLOCK_CANNON][1]);
      rect(cx - 11, cy - 11, 22, 22, 2);
      fill(BLOCK_COLORS[BLOCK_CANNON][2]);
      rect(cx - 11, cy + 7, 22, 4);
      fill(BLOCK_COLORS[BLOCK_CANNON][2]);
      circle(cx, cy - 2, 16);
      fill(BULLET_COLOR);
      circle(cx, cy - 2, 9);
    } else if (id.equals("spike")) {
      // the pyramid as seen in iso: dark left side, light front side
      noStroke();
      fill(SPIKE_COLORS[0]);
      triangle(cx, cy - 11, cx - 11, cy + 7, cx, cy + 11);
      fill(SPIKE_COLORS[1]);
      triangle(cx, cy - 11, cx, cy + 11, cx + 11, cy + 7);
    } else if (id.equals("view")) {
      // shows the view you are in: a cube for iso, a flat square for side
      drawIcon(isIso ? "view_iso" : "view_side", cx, cy);
    } else {
      drawIcon(id, cx, cy);
    }
  }

  // Draws a loaded icon image centred on (cx, cy)
  void drawIcon(String name, float cx, float cy) {
    PImage img = icons.get(name);
    if (img == null) return;
    imageMode(CENTER);
    noTint();
    image(img, cx, cy, ICON_DRAW, ICON_DRAW);
    imageMode(CORNER);
  }

  // A small iso cube made of three shaded rhombi, using a block type's face colours
  void drawCubeIcon(float cx, float cy, float r, int[] cols) {
    float h = r * 0.866;
    noStroke();
    fill(cols[2]);  // top
    quad(cx, cy - r, cx + h, cy - r / 2, cx, cy, cx - h, cy - r / 2);
    fill(cols[0]);  // left
    quad(cx - h, cy - r / 2, cx, cy, cx, cy + r, cx - h, cy + r / 2);
    fill(cols[1]);  // right
    quad(cx + h, cy - r / 2, cx, cy, cx, cy + r, cx + h, cy + r / 2);
  }

  void flash(String msg) {
    message = msg;
    messageUntil = millis() + 1500;
  }

  // input

  void mousePressed() {
    // the toolbar and help panel swallow clicks so they never edit the level behind them
    if (overUI(mouseX, mouseY)) {
      int t = toolAt(mouseX, mouseY);
      if (mouseButton == LEFT && t >= 0) useTool(TOOLS[t]);
      return;
    }

    // Right drag pans and middle drag orbits. A right click that never moves removes on release.
    if (mouseButton == RIGHT || mouseButton == CENTER) {
      dragging = true;
      dragButton = mouseButton;
      dragMoved = mouseButton == CENTER;
      dragStartX = lastDragX = mouseX;
      dragStartY = lastDragY = mouseY;
      return;
    }

    if (mouseButton == LEFT && tool == TOOL_SELECT) {
      leftDragging = true;
      startSelect(mouseX, mouseY);
      return;
    }
    if (mouseButton == LEFT && (tool == TOOL_SPAWN || tool == TOOL_GOAL)) {
      placeMarker(mouseX, mouseY);
      return;
    }
    if (mouseButton == LEFT && tool == TOOL_FILL) {
      startFill(mouseX, mouseY);
      leftDragging = filling;
      return;
    }

    if (mouseButton == LEFT) {
      int h = handleAt(mouseX, mouseY);
      if (h >= 0) {
        int[] d = DIRS[h];
        selected = grid.put(selected.x + d[0], selected.y + d[1], selected.z + d[2], brush);
        if (brush == BLOCK_CANNON && d[1] == 0) selected.dir = h;  // a cannon faces the way it was built out
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
    if (leftDragging) {
      if (tool == TOOL_SELECT) dragSelect(mouseX, mouseY);
      else if (filling) dragFill(mouseX, mouseY);
      return;
    }
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
    if (leftDragging && mouseButton == LEFT) {
      leftDragging = false;
      if (filling) finishFill();
      return;
    }
    if (!dragging) return;
    dragging = false;
    if (!dragMoved) {  // only a right press can reach here unmoved; middle starts as moved
      removeAt(cellAt(dragStartX, dragStartY));
    }
  }

  void mouseWheel(float count) {
    zoomAt(pow(1.1, -count), mouseX, mouseY);
  }

  void keyPressed() {
    setKeys(key, true);
    if (key == CODED && keyCode == SHIFT) shiftDown = true;

    char k = Character.toLowerCase(key);
    if (k == 'b') setTool(TOOL_BUILD);
    if (k == 'v') setTool(TOOL_SELECT);
    if (k == 'f') setTool(TOOL_FILL);
    if (k == 'p') setTool(TOOL_SPAWN);
    if (k == 'g') setTool(TOOL_GOAL);

    if (key == '1') brush = BLOCK_PLATFORM;
    if (key == '2') brush = BLOCK_CUBE;
    if (key == '3') brush = BLOCK_DOT;
    if (key == '4') brush = BLOCK_SPIKE;
    if (key == '5') brush = BLOCK_CANNON;
    if (k == 't') turnCannons();

    if ((key == 'r' || key == 'R') && !viewKeyDown) {
      viewKeyDown = true;
      toggleView();
    }
    if (key == DELETE || key == BACKSPACE) {
      if (!selection.isEmpty()) removeSelection();
      else if (selected != null) removeCell(selected);
    }
    if (key == ENTER || key == RETURN) save();
  }

  void keyReleased() {
    setKeys(key, false);
    if (key == CODED && keyCode == SHIFT) shiftDown = false;
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
