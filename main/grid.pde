import processing.awt.PGraphicsJava2D;
import java.awt.RenderingHints;

// The world as a grid of unit cells, used for drawing (in play and in the editor).
// Collision still uses the merged boxes in Level.objects.

final int BLOCK_PLATFORM = 0;
final int BLOCK_CUBE = 1;
final int BLOCK_DOT = 2;
final String[] BLOCK_NAMES = { "Platform", "Cube", "Dot" };
final float DOT_RADIUS = 0.25;

// left (-x), front (+z), top (+y) face colours per block type
final int[][] BLOCK_COLORS = {
  { #285AAA, #3C78D2, #5A96F0 },  // platform
  { #AA3C3C, #D25050, #F07878 },  // cube
};

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

  String keyOf(int x, int y, int z) { return x + "," + y + "," + z; }

  Cell get(int x, int y, int z) { return cells.get(keyOf(x, y, z)); }

  // Dots do not hide the faces of neighbouring blocks
  boolean solidAt(int x, int y, int z) {
    Cell c = get(x, y, z);
    return c != null && c.type != BLOCK_DOT;
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

  // The three faces the camera can see: 0 = left (-x), 1 = front (+z), 2 = top (+y)
  PVector[] faceCorners(int x, int y, int z, int face, float t) {
    float x0 = x, x1 = x + 1, y0 = y, y1 = y + 1, z0 = z, z1 = z + 1;
    float[][] p;
    if (face == 0)      p = new float[][] { { x0, y0, z0 }, { x0, y1, z0 }, { x0, y1, z1 }, { x0, y0, z1 } };
    else if (face == 1) p = new float[][] { { x0, y0, z1 }, { x0, y1, z1 }, { x1, y1, z1 }, { x1, y0, z1 } };
    else                p = new float[][] { { x0, y1, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, { x0, y1, z1 } };

    PVector[] s = new PVector[4];
    for (int i = 0; i < 4; i++) s[i] = worldToScreen(p[i][0], p[i][1], p[i][2], t);
    return s;
  }

  // A face is only drawn (and clickable) if no solid block sits against it
  boolean faceVisible(Cell c, int face) {
    if (face == 0) return !solidAt(c.x - 1, c.y, c.z);
    if (face == 1) return !solidAt(c.x, c.y, c.z + 1);
    return !solidAt(c.x, c.y + 1, c.z);
  }

  void drawCell(Cell c, float t, float alpha, boolean outline) {
    if (c.type == BLOCK_DOT) {
      PVector s = worldToScreen(c.x + 0.5, c.y + 0.5, c.z + 0.5, t);
      if (outline) {
        stroke(255);
        strokeWeight(2);
      } else {
        noStroke();
      }
      fill(255, 200, 60, alpha);
      circle(s.x, s.y, DOT_RADIUS * 2 * screenScale(t));
      return;
    }

    // Faces are drawn without anti-aliasing: with it, every edge shared by two cells
    // is only partly covered and shows as a faint grid line
    int[] cols = BLOCK_COLORS[c.type];
    noStroke();
    setAntialias(false);
    for (int f = 0; f < 3; f++) {
      if (!faceVisible(c, f)) continue;
      PVector[] q = faceCorners(c.x, c.y, c.z, f, t);
      if (abs(quadArea(q)) < 1) continue;  // seen edge-on (e.g. top face in side view)

      fill(cols[f], alpha);
      quad(q[0].x, q[0].y, q[1].x, q[1].y, q[2].x, q[2].y, q[3].x, q[3].y);
    }
    setAntialias(true);

    if (outline) {
      noFill();
      stroke(255, 200, 60);
      strokeWeight(2);
      for (int f = 0; f < 3; f++) {
        if (!faceVisible(c, f)) continue;
        PVector[] q = faceCorners(c.x, c.y, c.z, f, t);
        if (abs(quadArea(q)) < 1) continue;
        quad(q[0].x, q[0].y, q[1].x, q[1].y, q[2].x, q[2].y, q[3].x, q[3].y);
      }
    }
  }

  // Screen-space centre of a cell. A unit cell never extends more than
  // cellReach(t) pixels from it on screen.
  PVector screenCenter(Cell c, float t) {
    return worldToScreen(c.x + 0.5, c.y + 0.5, c.z + 0.5, t);
  }
}

// Switches anti-aliasing on the default (JAVA2D) renderer for the shapes drawn after it
void setAntialias(boolean on) {
  ((PGraphicsJava2D) g).g2.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
    on ? RenderingHints.VALUE_ANTIALIAS_ON : RenderingHints.VALUE_ANTIALIAS_OFF);
}

// Twice the signed area of a quad (shoelace formula)
float quadArea(PVector[] q) {
  float area = 0;
  for (int i = 0; i < 4; i++) {
    PVector a = q[i], b = q[(i + 1) % 4];
    area += a.x * b.y - b.x * a.y;
  }
  return area;
}

// true if (px, py) is inside the convex quad q (either winding). Faces seen edge-on never count.
boolean inQuad(float px, float py, PVector[] q) {
  if (abs(quadArea(q)) < 1) return false;
  boolean pos = false, neg = false;
  for (int i = 0; i < 4; i++) {
    PVector a = q[i], b = q[(i + 1) % 4];
    float cross = (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x);
    if (cross > 0) pos = true;
    if (cross < 0) neg = true;
  }
  return !(pos && neg);
}
