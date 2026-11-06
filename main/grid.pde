import java.util.HashSet;

// The world as a grid of unit cells, used for drawing (in play and in the editor).
// Collision still uses the merged boxes in Level.objects.

final int BLOCK_PLATFORM = 0;
final int BLOCK_CUBE = 1;
final int BLOCK_DOT = 2;
final String[] BLOCK_NAMES = { "Platform", "Cube", "Dot" };
final float DOT_RADIUS = 0.25;

// x faces, z faces, y faces colours per block type
// (left, front and top in the game's view)
final int[][] BLOCK_COLORS = {
  { #285AAA, #3C78D2, #5A96F0 },  // platform
  { #AA3C3C, #D25050, #F07878 },  // cube
};

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

  // Dots and see-through cells do not hide the faces of neighbouring blocks
  boolean solidAt(int x, int y, int z) {
    Cell c = get(x, y, z);
    return c != null && c.type != BLOCK_DOT && !seeThrough.contains(c);
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
    if (dots == null) return;
    for (int i = 0; i < dots.size(); i++) {
      PVector p = readVec(dots.getJSONObject(i).getJSONArray("pos"));
      put(floor(p.x), floor(p.y), floor(p.z), BLOCK_DOT);
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
    cellFaces(c.x, c.y, c.z, c.type, alpha, eye);
  }

  void cellFaces(int x, int y, int z, int type, float alpha, PVector eye) {
    int[] cols = BLOCK_COLORS[type];
    for (int i = 0; i < DIRS.length; i++) {
      int[] d = DIRS[i];
      if (dirDot(d, eye) <= 0.001 || solidAt(x + d[0], y + d[1], z + d[2])) continue;
      fill(cols[DIR_COLOR[i]], alpha);
      for (float[] p : faceCorners(x, y, z, d)) vertex(p[0], p[1], p[2]);
    }
  }
}

float dirDot(int[] d, PVector v) {
  return d[0] * v.x + d[1] * v.y + d[2] * v.z;
}
