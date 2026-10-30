import java.util.HashSet;

class Platform {
  PVector pos, size;
  color left  = color(40, 90, 170);
  color front = color(60, 120, 210);
  color top   = color(90, 150, 240);

  Platform(PVector pos, PVector size) {
    this.pos = pos;
    this.size = size;
  }
}

class Cube extends Platform {
  Cube(PVector pos, PVector size) {
    super(pos, size);
    left  = color(170, 60, 60);
    front = color(210, 80, 80);
    top   = color(240, 120, 120);
  }
}

class Dot {
  PVector pos;
  float radius;

  Dot(PVector pos, float radius) {
    this.pos = pos;
    this.radius = radius;
  }
}

// A dot or the player, placed into the sorted box list
class Item {
  PVector feet;   // x/z centre, y = feet (same convention as player.pos)
  float r;
  Dot dot;        // null means player
  int slot;       // how many boxes are drawn before this item
  float key;      // depth among items, far to near

  Item(PVector feet, float r, Dot dot) {
    this.feet = feet;
    this.r = r;
    this.dot = dot;
    key = -feet.x + feet.z + feet.y + r;
  }
}

class Level {
  String name;
  PVector spawn, goal;
  ArrayList<Platform> boxes = new ArrayList<Platform>(); // platforms and cubes
  ArrayList<Dot> dots = new ArrayList<Dot>();

  Level(String file) {
    JSONObject json = loadJSONObject("levels/" + file);
    name  = json.getString("name", file);
    spawn = readVec(json.getJSONArray("spawn"));
    goal  = readVec(json.getJSONArray("goal"));

    JSONArray ps = json.getJSONArray("platforms");
    if (ps != null) {
      for (int i = 0; i < ps.size(); i++) {
        JSONObject p = ps.getJSONObject(i);
        boxes.add(new Platform(readVec(p.getJSONArray("pos")), readVec(p.getJSONArray("size"))));
      }
    }

    JSONArray cs = json.getJSONArray("cubes");
    if (cs != null) {
      for (int i = 0; i < cs.size(); i++) {
        JSONObject c = cs.getJSONObject(i);
        boxes.add(new Cube(readVec(c.getJSONArray("pos")), readVec(c.getJSONArray("size"))));
      }
    }

    JSONArray ds = json.getJSONArray("dots");
    if (ds != null) {
      for (int i = 0; i < ds.size(); i++) {
        JSONObject d = ds.getJSONObject(i);
        dots.add(new Dot(readVec(d.getJSONArray("pos")), d.getFloat("radius", 0.5)));
      }
    }
  }

  void display(float t, Player player) {
    noStroke();

    ArrayList<Platform> sorted = sortBoxes(); // far to near

    // dots and player as items
    ArrayList<Item> items = new ArrayList<Item>();
    for (Dot d : dots) {
      items.add(new Item(new PVector(d.pos.x, d.pos.y - d.radius, d.pos.z), d.radius, d));
    }
    items.add(new Item(player.pos, player.radius, null));

    // each item goes after the last box that is NOT in front of it
    for (Item it : items) {
      it.slot = 0;
      for (int i = 0; i < sorted.size(); i++) {
        if (!inFront(sorted.get(i), it.feet, it.r)) it.slot = i + 1;
      }
    }
    items.sort((a, b) -> Float.compare(a.key, b.key)); // far to near

    // interleave boxes and items
    for (int i = 0; i <= sorted.size(); i++) {
      for (Item it : items) {
        if (it.slot == i) drawItem(it, t, player);
      }
      if (i < sorted.size()) {
        Platform p = sorted.get(i);
        drawBox(p.pos, p.size, t, p.left, p.front, p.top);
      }
    }
  }

  void drawItem(Item it, float t, Player player) {
    if (it.dot != null) {
      fill(255, 200, 60);
      PVector s = worldToScreen(it.dot.pos.x, it.dot.pos.y, it.dot.pos.z, t);
      circle(s.x, s.y, it.dot.radius * 2 * worldUnits);
    } else {
      player.display();
    }
  }

  // true if a must be drawn before b (a is fully behind b on some axis)
  boolean behind(Platform a, Platform b) {
    return a.pos.x >= b.pos.x + b.size.x          // a is on the +x side (camera sees -x)
        || a.pos.z + a.size.z <= b.pos.z          // a is on the -z side (camera sees +z)
        || a.pos.y + a.size.y <= b.pos.y;         // a is below b (camera sees +y)
  }

  ArrayList<Platform> sortBoxes() {
    ArrayList<Platform> out = new ArrayList<Platform>();
    HashSet<Platform> seen = new HashSet<Platform>();
    for (Platform p : boxes) visit(p, seen, out);
    return out;
  }

  void visit(Platform p, HashSet<Platform> seen, ArrayList<Platform> out) {
    if (seen.contains(p)) return;
    seen.add(p);
    for (Platform q : boxes) {
      if (q != p && behind(q, p)) visit(q, seen, out); // draw what's behind p first
    }
    out.add(p);
  }

  void drawBox(PVector pos, PVector size, float t, color left, color front, color top) {
    float x0 = pos.x, x1 = pos.x + size.x;
    float y0 = pos.y, y1 = pos.y + size.y;
    float z0 = pos.z, z1 = pos.z + size.z;

    // Left face (-x), only visible in iso
    fill(left);
    quadFace(x0, y0, z0,  x0, y1, z0,  x0, y1, z1,  x0, y0, z1,  t);

    // Front face (+z), the face you see in side view
    fill(front);
    quadFace(x0, y0, z1,  x0, y1, z1,  x1, y1, z1,  x1, y0, z1,  t);

    // Top face, only visible in iso
    fill(top);
    quadFace(x0, y1, z0,  x1, y1, z0,  x1, y1, z1,  x0, y1, z1,  t);
  }

  void quadFace(float ax, float ay, float az, float bx, float by, float bz, float cx, float cy, float cz, float dx, float dy, float dz, float t) {
    PVector a = worldToScreen(ax, ay, az, t);
    PVector b = worldToScreen(bx, by, bz, t);
    PVector c = worldToScreen(cx, cy, cz, t);
    PVector d = worldToScreen(dx, dy, dz, t);
    quad(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y);
  }

  boolean inFront(Platform b, PVector p, float r) {
    boolean xFront = b.pos.x + b.size.x <= p.x - r;  // box is on the -x side
    boolean zFront = b.pos.z >= p.z + r;             // box is on the +z side
    boolean yFront = b.pos.y >= p.y + 2 * r;         // box is above (pos.y = feet)
    return xFront || zFront || yFront;
  }
}

PVector readVec(JSONArray a) {
  return new PVector(a.getFloat(0), a.getFloat(1), a.getFloat(2));
}