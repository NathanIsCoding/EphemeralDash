import java.util.HashSet;

// The world as a grid of unit cells, used for drawing (in play and in the editor).
// Collision still uses the merged boxes in Level.objects.

final int BLOCK_PLATFORM = 0;
final int BLOCK_CUBE = 1;
final int BLOCK_DOT = 2;
final int BLOCK_SPIKE = 3;
final int BLOCK_CANNON = 4;
final String[] BLOCK_NAMES = { "Platform", "Cube", "Dot", "Spike", "Cannon" };
final float DOT_RADIUS = 0.25;
final float SPIKE_HEIGHT = 0.8;  // world units, tip above the cell floor
final float SPIKE_INSET = 0.2;   // hitbox is this much smaller than the base on each side

// -x, +z, +x, -z side colours of a spike
final int[] SPIKE_COLORS = { #8C8C96, #B4B4BE, #D2D2DC, #A0A0AA };

// Platforms and cubes are drawn as box faces from BLOCK_COLORS; dots and spikes are
// drawn as their own shapes and never hide a neighbour's faces
boolean isBlock(int type) {
  return type == BLOCK_PLATFORM || type == BLOCK_CUBE || type == BLOCK_CANNON;
}

// x faces, z faces, y faces colours per block type
// (left, front and top in the game's view). Only box types have colours.
final int[][] BLOCK_COLORS = {
  { #285AAA, #3C78D2, #5A96F0 },  // platform
  { #AA3C3C, #D25050, #F07878 },  // cube
  null,                           // dot
  null,                           // spike
  { #32323C, #464655, #5F5F73 },  // cannon
};

// Names of DIRS, as written in level files
final String[] DIR_NAMES = { "-x", "+x", "+y", "-y", "+z", "-z" };

int dirIndex(String name) {
  for (int i = 0; i < DIR_NAMES.length; i++) {
    if (DIR_NAMES[i].equals(name)) return i;
  }
  return 0;
}

// The directions a cannon can face, in the order T turns through them
// (a quarter turn each, seen from above): -x, -z, +x, +z
final int[] CANNON_DIRS = { 0, 5, 1, 4 };

// The six face directions of a cell
final int[][] DIRS = {
  { -1, 0, 0 }, { 1, 0, 0 },
  { 0, 1, 0 }, { 0, -1, 0 },
  { 0, 0, 1 }, { 0, 0, -1 }
};

// BLOCK_COLORS entry for each of DIRS
final int[] DIR_COLOR = { 0, 0, 2, 2, 1, 1 };

class Cell {
  int x, y, z, type;
  // cannons only: firing direction (index into DIRS) and timing
  int dir = 0;
  float interval = CANNON_INTERVAL, offset = 0;

  Cell(int x, int y, int z, int type) {
    this.x = x;
    this.y = y;
    this.z = z;
    this.type = type;
  }

  // World-space bounds, in the same form as GameObject.minB/maxB
  PVector minB() {
    if (type == BLOCK_DOT) return new PVector(x + 0.5 - DOT_RADIUS, y + 0.5 - DOT_RADIUS, z + 0.5 - DOT_RADIUS);
    return new PVector(x, y, z);
  }

  PVector maxB() {
    if (type == BLOCK_DOT) return new PVector(x + 0.5 + DOT_RADIUS, y + 0.5 + DOT_RADIUS, z + 0.5 + DOT_RADIUS);
    if (type == BLOCK_SPIKE) return new PVector(x + 1, y + SPIKE_HEIGHT, z + 1);
    return new PVector(x + 1, y + 1, z + 1);
  }
}

class CellGrid {
  HashMap<String, Cell> cells = new HashMap<String, Cell>();
  ArrayList<Cell> order;  // far-to-near draw order, rebuilt only when cells change
  // Cells drawn partly transparent. They do not hide their neighbours' faces,
  // or the background would show through them where those faces were skipped.
  java.util.Set<Cell> seeThrough = new HashSet<Cell>();

  String keyOf(int x, int y, int z) { return x + "," + y + "," + z; }

  Cell get(int x, int y, int z) { return cells.get(keyOf(x, y, z)); }

  // Dots, spikes and see-through cells do not hide the faces of neighbouring blocks
  boolean solidAt(int x, int y, int z) {
    Cell c = get(x, y, z);
    return c != null && isBlock(c.type) && !seeThrough.contains(c);
  }

  Cell put(int x, int y, int z, int type) {
    Cell c = new Cell(x, y, z, type);
    cells.put(keyOf(x, y, z), c);
    order = null;
    return c;
  }

  void remove(Cell c) {
    cells.remove(keyOf(c.x, c.y, c.z));
    order = null;
  }

  boolean isEmpty() { return cells.isEmpty(); }

  // Sorted by view depth (y + z - x, the axis the iso camera looks along).
  // For equal unit cells on a grid this is an exact painter's order.
  ArrayList<Cell> drawOrder() {
    if (order == null) {
      order = new ArrayList<Cell>(cells.values());
      order.sort((a, b) -> {
        int ka = a.y + a.z - a.x, kb = b.y + b.z - b.x;
        return ka != kb ? Integer.compare(ka, kb) : Integer.compare(a.y, b.y);
      });
    }
    return order;
  }

  // Splits each box from a level file into unit cells
  void addBoxes(JSONArray boxes, int type) {
    if (boxes == null) return;
    for (int i = 0; i < boxes.size(); i++) {
      JSONObject b = boxes.getJSONObject(i);
      PVector p = readVec(b.getJSONArray("pos"));
      PVector s = readVec(b.getJSONArray("size"));
      for (int x = floor(p.x); x < ceil(p.x + s.x); x++)
        for (int y = floor(p.y); y < ceil(p.y + s.y); y++)
          for (int z = floor(p.z); z < ceil(p.z + s.z); z++)
            put(x, y, z, type);
    }
  }

  void addDots(JSONArray dots) {
    addPoints(dots, BLOCK_DOT);
  }

  void addSpikes(JSONArray spikes) {
    addPoints(spikes, BLOCK_SPIKE);
  }

  void addCannons(JSONArray cannons) {
    if (cannons == null) return;
    for (int i = 0; i < cannons.size(); i++) {
      JSONObject n = cannons.getJSONObject(i);
      PVector p = readVec(n.getJSONArray("pos"));
      Cell c = put(floor(p.x), floor(p.y), floor(p.z), BLOCK_CANNON);
      c.dir = dirIndex(n.getString("dir", "-x"));
      c.interval = n.getFloat("interval", CANNON_INTERVAL);
      c.offset = n.getFloat("offset", 0);
    }
  }

  // One cell per item, at its "pos"
  void addPoints(JSONArray items, int type) {
    if (items == null) return;
    for (int i = 0; i < items.size(); i++) {
      PVector p = readVec(items.getJSONObject(i).getJSONArray("pos"));
      put(floor(p.x), floor(p.y), floor(p.z), type);
    }
  }

  // A face is only drawn if no solid block sits against it
  boolean faceOpen(Cell c, int[] d) {
    return !solidAt(c.x + d[0], c.y + d[1], c.z + d[2]);
  }

  // World-space corners of the face of cell (x, y, z) that points in direction d
  float[][] faceCorners(int x, int y, int z, int[] d) {
    int a = d[0] != 0 ? 0 : d[1] != 0 ? 1 : 2;  // axis the face is perpendicular to
    int u = (a + 1) % 3, v = (a + 2) % 3;
    int[][] uv = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
    float[][] out = new float[4][];
    for (int i = 0; i < 4; i++) {
      float[] p = { x, y, z };
      p[a] += d[a] > 0 ? 1 : 0;
      p[u] += uv[i][0];
      p[v] += uv[i][1];
      out[i] = p;
    }
    return out;
  }

  // Emits the faces of a block cell that face the camera (eye points toward it) and
  // are not covered by a neighbour. Call between beginShape(QUADS) and endShape().
  void cellFaces(Cell c, float alpha, PVector eye) {
    cellFaces(c.x, c.y, c.z, c.type, c.dir, alpha, eye);
  }

  void cellFaces(int x, int y, int z, int type, float alpha, PVector eye) {
    cellFaces(x, y, z, type, 0, alpha, eye);
  }

  // dir only matters for cannons: their body stops CANNON_OUT short of the cell on the
  // firing side, so the muzzle and lip fit inside the cell, flush with its edge
  void cellFaces(int x, int y, int z, int type, int dir, float alpha, PVector eye) {
    int[] cols = BLOCK_COLORS[type];
    int[] f = DIRS[dir];
    int fa = f[0] != 0 ? 0 : f[1] != 0 ? 1 : 2;
    for (int i = 0; i < DIRS.length; i++) {
      int[] d = DIRS[i];
      if (dirDot(d, eye) <= 0.001 || solidAt(x + d[0], y + d[1], z + d[2])) continue;
      fill(cols[DIR_COLOR[i]], alpha);
      for (float[] p : faceCorners(x, y, z, d)) {
        if (type == BLOCK_CANNON) {
          float lo = fa == 0 ? x : fa == 1 ? y : z;
          if (f[fa] > 0 && p[fa] > lo + 0.5) p[fa] = lo + 1 - CANNON_OUT;
          if (f[fa] < 0 && p[fa] < lo + 0.5) p[fa] = lo + CANNON_OUT;
        }
        vertex(p[0], p[1], p[2]);
      }
    }
  }
}

float dirDot(int[] d, PVector v) {
  return d[0] * v.x + d[1] * v.y + d[2] * v.z;
}
