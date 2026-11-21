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
final String[] TOOLS = { "build", "select", "fill", "|", "platform", "cube", "dot", "spike", "cannon", "|", "spawn", "goal", "|", "play", "playhere", "music", "view", "resetview", "resetzoom", "resetpos", "save", "help", "exit" };
final String[] HELP_LINES = {
  "Build [B]: click a block, then a handle to add",
  "Select [V]: drag between blocks to box-select, Shift adds",
  "Fill [F]: drag across a block face to place a line or plane",
  "Spawn [P] / Goal [G]: click a block to place it on top",
  "T: turn the selected cannon(s) a quarter turn",
  "Select cannon(s) to set their timing in the bottom-left panel",
  "Right click / Delete: remove (the whole selection if any)",
  "Timeline (bottom): click / drag to jump there, play previews from the view",
  "Space: play / pause the song preview",
  "  >> next to play: the view follows the preview along the level",
  "WASD / right drag: pan",
  "Wheel: zoom, Z: reset the zoom, H: back to the spawn",
  "Q/E / middle drag: rotate, C: reset the angle",
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
  { "resetview", "reset_shutter_speed" },
  { "resetzoom", "reset_focus" },
  { "resetpos",  "person_pin_circle" },
  { "save",      "save" },
  { "help",      "help" },
  { "music",     "music_note_add" },
  { "play",      "play_circle" },
  { "playhere",  "flag_circle" },
  { "stop",      "stop_circle" },  // the play-test's Stop button
  { "exit",      "logout" },
};
final float ICON_DRAW = 24;  // pixels; matches the images, so they are not resampled

final int TOOL_BUILD = 0, TOOL_SELECT = 1, TOOL_FILL = 2, TOOL_SPAWN = 3, TOOL_GOAL = 4;
final color SPAWN_COLOR = #FF5050, GOAL_COLOR = #50DC78;
// unsaved-changes dialog
final String[] EXIT_CHOICES = { "save", "discard", "cancel" };
final String[] EXIT_LABELS = { "Save & Exit", "Discard", "Cancel" };
final float DLG_BUTTON_W = 124, DLG_BUTTON_H = 36, DLG_GAP = 12;
final int MAX_FILL = 100;  // cells per side of one fill, so a slip of the mouse cannot place thousands
final float SCAN_MIN_WIDTH = 6;  // pixels: the preview's scan band never gets thinner than this
final float EXTRUDE_COS = 0.9;  // how closely a drag must follow a face normal on screen to extrude from it

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

  // Fill tool: a line or rectangle of cells from fillStart to fillEnd
  boolean filling;
  int[] fillStart, fillEnd;
  int fillAxis;            // axis of the clicked face's normal; the flat fill keeps it fixed
  int fillOut;             // +1 or -1: which way along fillAxis is out of the face
  boolean fillCanExtrude;  // false when the face points at the camera
  boolean fillExtruding;   // this drag is building out of the face, not flat against it
  float fillPressX, fillPressY;  // screen pixel where the fill drag began

  boolean isIso = true;
  float t = 1;  // view blend, same meaning as Player.shiftT: side view flattens yaw and pitch
  PVector cam;  // world point at the screen centre
  float yaw = ISO_YAW, pitch = ISO_PITCH;
  float zoom = 1;
  boolean dragging, dragMoved;
  int dragButton;
  float dragStartX, dragStartY, lastDragX, lastDragY;
  boolean panLeft, panRight, panUp, panDown, rotLeft, rotRight, viewKeyDown, spaceDown;

  CannonPanel cannonPanel = new CannonPanel();
  String savedText;            // serialize() output as of the last save (or when opened), for isDirty()
  boolean confirmExit = false; // the unsaved-changes dialog is open
  String message = "";
  int messageUntil = 0;
  boolean showHelp = false;
  boolean showMusic = false;
  String track;  // the level's music file in data/music, or null
  MusicPanel musicPanel = new MusicPanel();
  Timeline timeline = new Timeline();

  HashMap<String, PImage> icons = new HashMap<String, PImage>();

  Editor(String file) {
    this.file = file;
    for (String[] f : ICON_FILES) {
      icons.put(f[0], loadImage("icons/" + f[1] + "_" + ICON_SIZE + ".png"));
    }
    load();
    savedText = join(serialize(), "\n");  // an untouched level (even a new one) has nothing to save
    cam = spawn.copy();
  }

  OrthoView view() {
    return new OrthoView(cam, yaw * t, pitch * t, screenScale(t) * zoom);
  }

  // load / save 

  void load() {
    if (!levelExists(file)) {
      newLevel();
      return;
    }
    JSONObject json = loadJSONObject("levels/" + file);
    name = json.getString("name", file);
    track = json.getString("music", null);
    spawn = readVec(json.getJSONArray("spawn"));
    goal = readVec(json.getJSONArray("goal"));
    grid.addBoxes(json.getJSONArray("platforms"), BLOCK_PLATFORM);
    grid.addBoxes(json.getJSONArray("cubes"), BLOCK_CUBE);
    grid.addDots(json.getJSONArray("dots"));
    grid.addSpikes(json.getJSONArray("spikes"));
    grid.addCannons(json.getJSONArray("cannons"));
  }

  // A fresh level for an empty slot: a short 3-lane runway with the spawn at one
  // end and the goal at the other. It is written to disk on the first save.
  void newLevel() {
    String digits = file.replaceAll("[^0-9]", "");
    name = digits.isEmpty() ? file : "Level " + digits;
    spawn = new PVector(-1.5, 0, 1.5);
    goal = new PVector(9.5, 0, 1.5);
    for (int x = -2; x < 10; x++)
      for (int z = 0; z < 3; z++)
        grid.put(x, -1, z, BLOCK_PLATFORM);
    flash("New level: " + file);
  }

  void save() {
    String[] lines = serialize();
    saveStrings(dataPath("levels/" + file), lines);
    savedText = join(lines, "\n");
    flash("Saved " + file);
  }

  // Unsaved changes: the level as it would be saved now differs from the last save
  // (or from how it was when opened). Comparing the output catches every kind of edit.
  boolean isDirty() {
    return !join(serialize(), "\n").equals(savedText);
  }

  // The level as it is now, saved or not, for a play-test
  JSONObject levelJSON() {
    return parseJSONObject(join(serialize(), "\n"));
  }

  // The level file's lines, in the normal level format
  String[] serialize() {
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
    if (track != null) out.add("  \"music\": " + compactJSON(track) + ",");  // left out when there is none
    out.add("  \"spawn\": " + compactJSON(vecJSON(spawn)) + ",");
    out.add("  \"goal\": " + compactJSON(vecJSON(goal)) + ",");
    addJSONList(out, "platforms", mergeBoxes(BLOCK_PLATFORM), true);
    addJSONList(out, "cubes", mergeBoxes(BLOCK_CUBE), true);
    addJSONList(out, "dots", ds, true);
    addJSONList(out, "spikes", ss, true);
    addJSONList(out, "cannons", ns, false);
    out.add("}");
    return out.toArray(new String[0]);
  }

  // exit, with a warning when there are unsaved changes

  // The exit button and Esc
  void requestExit() {
    if (isDirty()) confirmExit = true;
    else exitEditor();
  }

  // Esc backs out of whatever is open, innermost first
  void escape() {
    if (cancelTyping()) return;
    if (confirmExit) confirmExit = false;
    else if (showMusic) showMusic = false;
    else requestExit();
  }

  void answerExit(String choice) {
    confirmExit = false;
    if (choice.equals("save")) {
      save();
      exitEditor();
    } else if (choice.equals("discard")) {
      exitEditor();
    }
    // "cancel": back to editing
  }

  // x, y, w, h of dialog button i
  float[] exitButtonRect(int i) {
    float total = EXIT_CHOICES.length * DLG_BUTTON_W + (EXIT_CHOICES.length - 1) * DLG_GAP;
    return new float[] { (width - total) / 2 + i * (DLG_BUTTON_W + DLG_GAP), height / 2 + 10, DLG_BUTTON_W, DLG_BUTTON_H };
  }

  int exitButtonAt(float mx, float my) {
    for (int i = 0; i < EXIT_CHOICES.length; i++) {
      float[] r = exitButtonRect(i);
      if (inRect(mx, my, r[0], r[1], r[2], r[3])) return i;
    }
    return -1;
  }

  void drawExitDialog() {
    noStroke();
    fill(0, 150);
    rect(0, 0, width, height);

    float w = 440, h = 140;
    float x = (width - w) / 2, y = height / 2 - 80;
    fill(30, 240);
    stroke(255, 60);
    strokeWeight(1);
    rect(x, y, w, h, 10);

    textAlign(CENTER, CENTER);
    noStroke();
    fill(255);
    textSize(20);
    text("Unsaved changes", width / 2, y + 30);
    textSize(14);
    fill(190);
    text("Save " + file + " before leaving?", width / 2, y + 60);

    int hover = exitButtonAt(mouseX, mouseY);
    for (int i = 0; i < EXIT_CHOICES.length; i++) {
      float[] r = exitButtonRect(i);
      boolean primary = i == 0;  // highlighted as the usual choice
      fill(i == hover ? color(255, 200, 60, 90) : primary ? color(255, 200, 60, 40) : color(255, 20));
      stroke(primary || i == hover ? color(255, 200, 60) : color(255, 70));
      strokeWeight(primary ? 2 : 1);
      rect(r[0], r[1], r[2], r[3], 6);
      noStroke();
      fill(255);
      textSize(15);
      text(EXIT_LABELS[i], r[0] + r[2] / 2, r[1] + r[3] / 2 - 1);
    }
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

  // Picking a block while the spawn or goal tool is active switches to the
  // build tool, since those tools can't place blocks
  void setBrush(int b) {
    brush = b;
    if (tool == TOOL_SPAWN || tool == TOOL_GOAL) setTool(TOOL_BUILD);
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

  // The cannons in the selection, or the build tool's cell if it is a cannon
  ArrayList<Cell> targetCannons() {
    ArrayList<Cell> targets = new ArrayList<Cell>(selection);
    if (targets.isEmpty() && selected != null) targets.add(selected);
    ArrayList<Cell> cannons = new ArrayList<Cell>();
    for (Cell c : targets) if (c.type == BLOCK_CANNON) cannons.add(c);
    return cannons;
  }

  // Turns every target cannon a quarter turn
  void turnCannons() {
    ArrayList<Cell> cannons = targetCannons();
    for (Cell c : cannons) {
      int i = 0;
      while (i < CANNON_DIRS.length && CANNON_DIRS[i] != c.dir) i++;
      c.dir = CANNON_DIRS[(i + 1) % CANNON_DIRS.length];  // an unknown dir starts over at -x
    }
    if (cannons.isEmpty()) flash("Select a cannon to turn it");
  }

  // Esc while typing in the cannon panel cancels the typing instead of leaving the editor
  boolean cancelTyping() {
    if (cannonPanel.editing < 0) return false;
    cannonPanel.cancel();
    return true;
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

  // The run goes in +x and is won by crossing the goal's x, so the goal must be
  // ahead of the spawn: a goal behind it could never be reached (or would win at once)
  boolean markerAllowed(PVector p) {
    return tool == TOOL_SPAWN ? p.x < goal.x : p.x > spawn.x;
  }

  void placeMarker(float sx, float sy) {
    PVector p = markerSpot(sx, sy);
    if (p == null) {
      flash("Click the top of a block with free space above it");
      return;
    }
    if (!markerAllowed(p)) {
      flash(tool == TOOL_SPAWN ? "The spawn must be before the goal" : "The goal must be ahead of the spawn");
      return;
    }
    if (tool == TOOL_SPAWN) spawn = p;
    else goal = p;
  }

  // fill tool

  // The fill starts in the cell just outside the clicked face. A face pointing
  // straight at the camera (as in side view) cannot be built out from, the same
  // as with handles, so then it starts from the clicked cell itself (which is
  // skipped, being taken).
  void startFill(float sx, float sy) {
    Cell c = cellAt(sx, sy);
    if (c == null) return;
    int[] d = DIRS[faceAt(c, sx, sy)];
    boolean facing = abs(dirDot(d, view().eye())) >= 0.95;
    fillAxis = axisOf(d);
    fillOut = d[fillAxis];
    fillCanExtrude = !facing;
    fillExtruding = false;
    fillStart = facing ? new int[] { c.x, c.y, c.z } : new int[] { c.x + d[0], c.y + d[1], c.z + d[2] };
    fillEnd = fillStart.clone();
    fillPressX = sx;
    fillPressY = sy;
    filling = true;
  }

  // The axis an extruded line widens along. On screen, sideways from the line could
  // mean either of the two other axes, so: a line out of a side face widens flat,
  // into a floor (along the other horizontal axis). A column widens along whichever
  // of x / z the drag follows more closely. Holding Shift picks the other one.
  int extrudeWidthAxis(OrthoView v, PVector drag) {
    int a = (fillAxis + 1) % 3, b = (fillAxis + 2) % 3;  // the two candidates
    int pick;
    if (fillAxis != 1) {
      pick = a == 1 ? b : a;  // the horizontal one
    } else {
      PVector ua = axisOnScreen(v, a), ub = axisOnScreen(v, b);
      float ca = abs(drag.dot(ua)) / max(ua.mag(), 1e-6);
      float cb = abs(drag.dot(ub)) / max(ub.mag(), 1e-6);
      pick = ca >= cb ? a : b;
    }
    if (shiftDown) pick = pick == a ? b : a;
    return pick;
  }

  // Screen pixels moved by one cell step along world axis a
  PVector axisOnScreen(OrthoView v, int a) {
    PVector e = v.rotate(new PVector(a == 0 ? 1 : 0, a == 1 ? 1 : 0, a == 2 ? 1 : 0));
    return new PVector(e.x * v.s, -e.y * v.s);
  }

  // Two ways to fill:
  // - Dragging straight out from the clicked face (along its normal, on screen)
  //   extrudes a line out of it, e.g. a column up from a top face. Once started,
  //   it stays an extrusion while it reaches at least one cell out, and dragging
  //   sideways widens the line into a plane (see extrudeWidthAxis).
  // - Any other drag fills a line or rectangle flat in the layer against the face:
  //   the mouse ray meets the layer's mid-plane, and the cell there is the far corner.
  void dragFill(float sx, float sy) {
    OrthoView v = view();
    PVector drag = new PVector(sx - fillPressX, sy - fillPressY);
    int[] e = fillStart.clone();

    PVector n = axisOnScreen(v, fillAxis);
    boolean usableN = fillCanExtrude && drag.mag() > 4 && n.mag() > v.s * 0.3;
    if (usableN && !fillExtruding && abs(drag.dot(n)) / (drag.mag() * n.mag()) > EXTRUDE_COS) {
      fillExtruding = true;
    }
    if (usableN && fillExtruding) {
      int b = extrudeWidthAxis(v, drag);
      PVector w = axisOnScreen(v, b);
      // split the drag exactly into steps out of the face (along n) and sideways (along w)
      float det = n.x * w.y - n.y * w.x;
      float out = drag.dot(n) / n.magSq(), side = 0;
      if (abs(det) > 1e-3) {
        out = (drag.x * w.y - drag.y * w.x) / det;
        side = (n.x * drag.y - n.y * drag.x) / det;
      }
      // outward only: dragging back into the block would build through it
      int steps = constrain(round(fillOut * out), 0, MAX_FILL - 1);
      if (steps > 0) {
        e[fillAxis] += fillOut * steps;
        e[b] += constrain(round(side), -(MAX_FILL - 1), MAX_FILL - 1);
        fillEnd = e;
        return;
      }
      fillExtruding = false;  // pulled back to the face: free to start a flat fill
    }

    PVector[] r = mouseRay(sx, sy);
    float da = getAxis(r[1], fillAxis);
    if (abs(da) < 0.05) return;  // looking along the layer edge-on: no sensible point
    float s = (fillStart[fillAxis] + 0.5 - getAxis(r[0], fillAxis)) / da;
    PVector p = PVector.add(r[0], PVector.mult(r[1], s));
    int[] hit = { floor(p.x), floor(p.y), floor(p.z) };
    for (int a = 0; a < 3; a++) {
      if (a != fillAxis) e[a] = constrain(hit[a], fillStart[a] - (MAX_FILL - 1), fillStart[a] + (MAX_FILL - 1));
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
    pivotOnCentre();
    isIso = !isIso;
  }

  // Slides cam along the view direction onto the block at the screen centre, if any
  void pivotOnCentre() {
    PVector[] r = mouseRay(width / 2, height / 2);
    float best = Float.MAX_VALUE;
    for (Cell c : grid.cells.values()) {
      float s = rayEntry(r[0], r[1], c.minB(), c.maxB());
      if (s >= 0 && s < best) best = s;
    }
    if (best < Float.MAX_VALUE) cam = PVector.add(r[0], PVector.mult(r[1], best));
  }

  // Back to the starting iso angle, turning about what is at the centre of the screen
  // (as toggleView does), so the view stays on the same part of the level. The zoom is kept.
  void resetView() {
    pivotOnCentre();
    yaw = ISO_YAW;
    pitch = ISO_PITCH;
    isIso = true;
  }

  // Song time and level x. The run speed is constant, so seconds into the song are
  // distance from the spawn (the same mapping startAttempt uses for "play from here").
  float timeAt(float x) {
    return (x - spawn.x) / RUN_SPEED;
  }

  float xAt(float t) {
    return spawn.x + t * RUN_SPEED;
  }

  // World x seen at screen x sx, at the middle of the screen's height: where the
  // view ray through that pixel crosses the camera point's lane (the z = cam.z plane).
  // In side view the ray runs along z, so any point on it will do.
  float visibleX(float sx) {
    OrthoView v = view();
    PVector p = v.fromScreen(sx, height / 2), d = v.eye();
    if (abs(d.z) > 0.05) p.add(PVector.mult(d, (cam.z - p.z) / d.z));
    return p.x;
  }

  // the song time at the centre of the screen
  float centreTime() {
    return timeAt(visibleX(width / 2));
  }

  // Slides the view along the level so time t is at the centre of the screen
  void centreOnTime(float t) {
    cam.x += xAt(t) - visibleX(width / 2);
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

    timeline.update(this, dt);  // after the view settles, so following uses this frame's view

    // a track picked in the Import... file dialog (which reports on its own thread)
    File picked = pickedMusicFile;
    if (picked != null) {
      pickedMusicFile = null;
      importTrack(picked);
    }
  }

  // music

  void toggleMusicPanel() {
    showMusic = !showMusic;
    if (showMusic) {
      showHelp = false;  // they open in the same spot
      musicPanel.refresh();
    }
  }

  // Positions the panel under the music button
  void placeMusicPanel() {
    float[] xs = toolXs();
    for (int i = 0; i < TOOLS.length; i++) if (TOOLS[i].equals("music")) musicPanel.x = xs[i];
    musicPanel.x = min(musicPanel.x, width - MP_W - TB_X);
    musicPanel.y = TB_Y + toolbarHeight() + 8;
  }

  // Hands over to the game to play this level as it is now, from the spawn or from
  // `from`; Esc comes back here unchanged
  void playTest(PVector from) {
    cannonPanel.commit(targetCannons());  // a typed value that was not applied yet still counts
    dragging = leftDragging = filling = shiftDown = false;
    panLeft = panRight = panUp = panDown = rotLeft = rotRight = false;  // their key-ups go to the game
    startTest(from);
  }

  // Play-test from on top of the selected block (the build tool's block, or the
  // leftmost of a selection), with the music at the matching time
  void playFromHere() {
    ArrayList<Cell> picked = new ArrayList<Cell>(selection);
    if (picked.isEmpty() && selected != null) picked.add(selected);
    Cell start = null;
    for (Cell c : picked) {
      // leftmost; among those the highest, which is the one you stand on
      if (start == null || c.x < start.x || (c.x == start.x && c.y > start.y)) start = c;
    }
    if (start == null) {
      flash("Select a block to start from");
      return;
    }
    if (grid.get(start.x, start.y + 1, start.z) != null) {
      flash("The block to start from needs free space above it");
      return;
    }
    if (start.x + 0.5 >= goal.x) {
      flash("Start before the goal");
      return;
    }
    playTest(new PVector(start.x + 0.5, start.y + 1, start.z + 0.5));
  }

  void setTrack(String t) {
    boolean wasPreviewing = music.playing();
    track = t;
    if (wasPreviewing && t != null) music.start(t);  // keep previewing, now the new track
    else music.stop();
  }

  void importTrack(File f) {
    if (!isMusicFile(f.getName())) {
      flash("Pick an .mp3 or .wav file");
      return;
    }
    String name = importMusic(f);
    if (name == null) {
      flash("Could not import " + f.getName());
      return;
    }
    musicPanel.refresh();
    setTrack(name);
    flash("Imported " + name);
  }

  // Deletes a track file once its x has been clicked twice in a row. The first click
  // says what else would lose it, since other saved levels may use the same file.
  void deleteTrackPressed(int row) {
    String t = musicPanel.trackFor(row);
    if (musicPanel.pendingDelete != row) {
      musicPanel.pendingDelete = row;
      ArrayList<String> others = levelsUsingTrack(t, file);
      flash("Click again to delete " + t
        + (others.isEmpty() ? "" : "  (also used by " + join(others.toArray(new String[0]), ", ") + ")"));
      return;
    }
    boolean wasCurrent = t.equals(track);
    if (wasCurrent) setTrack(null);  // the level goes silent; save to keep that
    if (!deleteMusic(t)) {
      musicPanel.pendingDelete = -1;
      flash("Could not delete " + t);
      return;
    }
    musicPanel.refresh();
    flash("Deleted " + t + (wasCurrent ? " - this level now has no music" : ""));
  }

  void musicPanelPressed() {
    int del = musicPanel.deleteAt(mouseX, mouseY);
    if (del >= 0) {
      deleteTrackPressed(del);
      return;
    }
    musicPanel.pendingDelete = -1;  // any other click cancels a pending delete
    int row = musicPanel.rowAt(mouseX, mouseY);
    if (row >= 0) {
      setTrack(musicPanel.trackFor(row));
      return;
    }
    int b = musicPanel.buttonAt(mouseX, mouseY);
    if (b == 0) {
      selectInput("Choose a music track (.mp3 or .wav)", "musicFileChosen");
    } else if (b == 1 && track != null) {
      if (music.playing()) music.stop();
      else music.start(track);
    }
  }

  void display() {
    OrthoView v = view();
    PVector eye = v.eye();
    int hover = overUI(mouseX, mouseY) ? -1 : handleAt(mouseX, mouseY);

    // the level, in world space
    grid.goalX = floor(goal.x);  // checkered goal line, following the goal as it is moved
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
    if (timeline.showBand(this)) drawScanBand(xAt(timeline.bandTime()), v);
    drawSelection(v);
    if (tool == TOOL_BUILD && selected != null) drawOutline(selected, v);
    drawMarker(spawn, SPAWN_COLOR, v);
    drawMarker(goal, GOAL_COLOR, v);
    if ((tool == TOOL_SPAWN || tool == TOOL_GOAL) && !overUI(mouseX, mouseY)) {
      PVector p = markerSpot(mouseX, mouseY);
      // a spot the marker cannot go shows as a faint grey ring
      if (p != null) drawMarker(p, markerAllowed(p) ? color(tool == TOOL_SPAWN ? SPAWN_COLOR : GOAL_COLOR, 110) : color(150, 70), v);
    }
    if (tool == TOOL_BUILD && selected != null) drawHandles(hover, v);
    // P3D draws a batch's outlines after its fills, so without these flushes the
    // marker rings above would show through the panels drawn over them
    flush();
    drawHud();
    if (confirmExit) {
      flush();
      drawExitDialog();
    }
  }

  // While the song is previewed: a see-through band, straight up and down the screen,
  // where the player would be at that moment of the song. It is placed on the middle
  // lane and is as wide as a block there. Call in screen space.
  void drawScanBand(float x, OrthoView v) {
    int z0 = floor(spawn.z), z1 = z0;
    for (Cell c : grid.cells.values()) {
      z0 = min(z0, c.z);
      z1 = max(z1, c.z);
    }
    float z = (z0 + z1 + 1) / 2.0;
    // screen x does not depend on height, so any y will do
    float a = v.toScreen(new PVector(x - 0.5, 0, z)).x, b = v.toScreen(new PVector(x + 0.5, 0, z)).x;
    float w = max(SCAN_MIN_WIDTH, abs(b - a));
    noStroke();
    fill(255, 200, 60, 45);
    rect((a + b) / 2 - w / 2, 0, w, height);
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

  // true over the toolbar, help or cannon panel, where clicks should not reach the level
  boolean overUI(float mx, float my) {
    if (inRect(mx, my, TB_X, TB_Y, toolbarWidth(), toolbarHeight())) return true;
    if (timeline.over(mx, my)) return true;
    if (cannonPanel.over(mx, my) && !targetCannons().isEmpty()) return true;
    if (showMusic) {
      placeMusicPanel();
      if (musicPanel.over(mx, my)) return true;
    }
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
    else if (id.equals("platform")) setBrush(BLOCK_PLATFORM);
    else if (id.equals("cube")) setBrush(BLOCK_CUBE);
    else if (id.equals("dot")) setBrush(BLOCK_DOT);
    else if (id.equals("spike")) setBrush(BLOCK_SPIKE);
    else if (id.equals("cannon")) setBrush(BLOCK_CANNON);
    else if (id.equals("view")) toggleView();
    else if (id.equals("resetview")) resetView();
    else if (id.equals("resetzoom")) zoom = 1;
    else if (id.equals("resetpos")) cam = spawn.copy();
    else if (id.equals("save")) save();
    else if (id.equals("music")) toggleMusicPanel();
    else if (id.equals("play")) playTest(null);
    else if (id.equals("playhere")) playFromHere();
    else if (id.equals("help")) {
      showHelp = !showHelp;
      if (showHelp) showMusic = false;  // they open in the same spot
    }
    else if (id.equals("exit")) requestExit();
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
    if (id.equals("music")) return showMusic;
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
    if (id.equals("resetview")) return "Reset the camera angle  [C]";
    if (id.equals("resetzoom")) return "Reset the zoom  [Z]";
    if (id.equals("resetpos")) return "Back to the spawn  [H]";
    if (id.equals("save")) return "Save  [Enter]";
    if (id.equals("help")) return "Controls";
    if (id.equals("music")) return "Level music" + (track != null ? ": " + track : "");
    if (id.equals("play")) return "Play-test from the spawn  (Esc stops)";
    if (id.equals("playhere")) return "Play-test from the selected block, music in sync";
    if (id.equals("exit")) return "Exit  [Esc]";
    return "";
  }

  void drawHud() {
    float[] xs = toolXs();
    float by = TB_Y + TB_PAD;
    int hoverTool = toolAt(mouseX, mouseY);

    timeline.display(this);

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

    ArrayList<Cell> cannons = targetCannons();
    if (!cannons.isEmpty()) cannonPanel.display(cannons);
    else cannonPanel.cancel();  // the cannons it was editing are no longer targeted

    if (showHelp) drawHelp();
    if (showMusic) {
      placeMusicPanel();
      musicPanel.display(track, music.playing());
    }
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
    } else if (id.equals("music")) {
      // tinted gold when the level has a track
      PImage img = icons.get("music");
      if (img == null) return;
      imageMode(CENTER);
      if (track != null) tint(255, 200, 60);
      else noTint();
      image(img, cx, cy, ICON_DRAW, ICON_DRAW);
      noTint();
      imageMode(CORNER);
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
    // the dialog is modal: only its buttons respond
    if (confirmExit) {
      int b = exitButtonAt(mouseX, mouseY);
      if (mouseButton == LEFT && b >= 0) answerExit(EXIT_CHOICES[b]);
      return;
    }
    ArrayList<Cell> cannons = targetCannons();
    if (!cannons.isEmpty() && cannonPanel.over(mouseX, mouseY)) {
      if (mouseButton == LEFT) cannonPanel.mousePressed(cannons);
      return;
    }
    // clicking anywhere else finishes typing, before the click can change the selection
    cannonPanel.commit(cannons);

    if (showMusic) {
      placeMusicPanel();
      if (musicPanel.over(mouseX, mouseY)) {
        if (mouseButton == LEFT) musicPanelPressed();
        return;
      }
    }

    if (timeline.over(mouseX, mouseY)) {
      if (mouseButton == LEFT) timeline.pressed(this);
      return;
    }

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
    if (confirmExit) return;
    if (cannonPanel.dragging >= 0) {
      cannonPanel.mouseDragged(targetCannons());
      return;
    }
    if (timeline.scrubbing) {
      timeline.scrubTo(this, mouseX);
      return;
    }
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
    if (cannonPanel.dragging >= 0 && mouseButton == LEFT) {
      cannonPanel.dragging = -1;
      return;
    }
    if (timeline.scrubbing && mouseButton == LEFT) {
      timeline.released(this);
      return;
    }
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
    if (confirmExit) return;
    if (showMusic) {
      placeMusicPanel();
      if (musicPanel.over(mouseX, mouseY)) {
        musicPanel.wheel(count);  // scroll the track list instead of zooming
        return;
      }
    }
    if (timeline.over(mouseX, mouseY)) return;
    zoomAt(pow(1.1, -count), mouseX, mouseY);
  }

  void keyPressed() {
    if (confirmExit) return;  // answered with the mouse; Esc (cancel) is handled by escape()
    // typing a value: keys like 1-5, Delete and Enter must not reach the tools
    if (cannonPanel.editing >= 0) {
      cannonPanel.keyPressed(targetCannons());
      return;
    }
    setKeys(key, true);
    if (key == CODED && keyCode == SHIFT) shiftDown = true;

    char k = Character.toLowerCase(key);
    if (k == 'b') setTool(TOOL_BUILD);
    if (k == 'v') setTool(TOOL_SELECT);
    if (k == 'f') setTool(TOOL_FILL);
    if (k == 'p') setTool(TOOL_SPAWN);
    if (k == 'g') setTool(TOOL_GOAL);

    if (key == '1') setBrush(BLOCK_PLATFORM);
    if (key == '2') setBrush(BLOCK_CUBE);
    if (key == '3') setBrush(BLOCK_DOT);
    if (key == '4') setBrush(BLOCK_SPIKE);
    if (key == '5') setBrush(BLOCK_CANNON);
    if (k == 't') turnCannons();

    if ((key == 'r' || key == 'R') && !viewKeyDown) {
      viewKeyDown = true;
      toggleView();
    }
    if (k == 'c') resetView();
    if (k == 'z') zoom = 1;  // the screen centre stays put, as cam is the point there
    if (k == 'h') cam = spawn.copy();
    if (key == ' ' && !spaceDown) {  // ignore key repeat, which would flick it on and off
      spaceDown = true;
      timeline.togglePlay(this);
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
    if (key == ' ') spaceDown = false;
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
