class Platform {
  PVector pos, size;
  Platform(PVector pos, PVector size) { this.pos = pos; this.size = size; }
}

class Dot {
  PVector pos;
  float radius;
  Dot(PVector pos, float radius) { this.pos = pos; this.radius = radius; }
}

class Level {
  String name;
  PVector spawn, goal;
  ArrayList<Platform> platforms = new ArrayList<Platform>();
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
        platforms.add(new Platform(readVec(p.getJSONArray("pos")),
                                   readVec(p.getJSONArray("size"))));
      }
    }

    JSONArray ds = json.getJSONArray("dots");
    if (ds != null) {
      for (int i = 0; i < ds.size(); i++) {
        JSONObject d = ds.getJSONObject(i);
        dots.add(new Dot(readVec(d.getJSONArray("pos")),
                         d.getFloat("radius", 0.5)));
      }
    }
  }

  void display(float t) {
  noStroke();

  for (Platform p : platforms) {
    float x0 = p.pos.x, x1 = p.pos.x + p.size.x;
    float y0 = p.pos.y, y1 = p.pos.y + p.size.y;
    float z0 = p.pos.z, z1 = p.pos.z + p.size.z;

    // Left face (-x), only visible in iso
    fill(40, 90, 170);
    quadFace(x0, y0, z0,  x0, y1, z0,  x0, y1, z1,  x0, y0, z1,  t);

    // Front face (+z), the face you see in side view
    fill(60, 120, 210);
    quadFace(x0, y0, z1,  x0, y1, z1,  x1, y1, z1,  x1, y0, z1,  t);

    // Top face, only visible in iso
    fill(90, 150, 240);
    quadFace(x0, y1, z0,  x1, y1, z0,  x1, y1, z1,  x0, y1, z1,  t);
  }

  fill(255, 200, 60);
  for (Dot d : dots) {
    PVector s = worldToScreen(d.pos.x, d.pos.y, d.pos.z, t);
    circle(s.x, s.y, d.radius * 2 * worldUnits);
  }
}

void quadFace(float ax, float ay, float az, float bx, float by, float bz,float cx, float cy, float cz, float dx, float dy, float dz, float t) {
  PVector a = worldToScreen(ax, ay, az, t);
  PVector b = worldToScreen(bx, by, bz, t);
  PVector c = worldToScreen(cx, cy, cz, t);
  PVector d = worldToScreen(dx, dy, dz, t);
  quad(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y);
}
}

PVector readVec(JSONArray a) {
  return new PVector(a.getFloat(0), a.getFloat(1), a.getFloat(2));
}