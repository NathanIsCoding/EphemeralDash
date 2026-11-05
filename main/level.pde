class Level {
  String name;
  PVector spawn, goal;
  ArrayList<GameObject> objects = new ArrayList<GameObject>(); // static world objects

  Level(String file) {
    JSONObject json = loadJSONObject("levels/" + file);
    name = json.getString("name", file);
    spawn = readVec(json.getJSONArray("spawn"));
    goal = readVec(json.getJSONArray("goal"));

    JSONArray ps = json.getJSONArray("platforms");
    if (ps != null) {
      for (int i = 0; i < ps.size(); i++) {
        JSONObject p = ps.getJSONObject(i);
        objects.add(new Platform(readVec(p.getJSONArray("pos")), readVec(p.getJSONArray("size"))));
      }
    }

    JSONArray cs = json.getJSONArray("cubes");
    if (cs != null) {
      for (int i = 0; i < cs.size(); i++) {
        JSONObject c = cs.getJSONObject(i);
        objects.add(new Cube(readVec(c.getJSONArray("pos")), readVec(c.getJSONArray("size"))));
      }
    }

    JSONArray ds = json.getJSONArray("dots");
    if (ds != null) {
      for (int i = 0; i < ds.size(); i++) {
        JSONObject d = ds.getJSONObject(i);
        objects.add(new Dot(readVec(d.getJSONArray("pos")), d.getFloat("radius", 0.5)));
      }
    }
  }

  boolean collides(PVector min, PVector max, boolean is3D) {
    for (GameObject o : objects) {
      if (o.collides(min, max, is3D)) return true;
    }
    return false;
  }

  // Every object the box overlaps
  ArrayList<GameObject> hits(PVector min, PVector max, boolean is3D) {
    ArrayList<GameObject> out = new ArrayList<GameObject>();
    for (GameObject o : objects) {
      if (o.collides(min, max, is3D)) out.add(o);
    }
    return out;
  }

  // Height of the highest box top under the footprint [x0, x1] x [z0, z1]
  // at or below y, or NaN if none
  float groundBelow(float x0, float x1, float y, float z0, float z1) {
    float best = Float.NaN;
    for (GameObject o : objects) {
      if (!(o instanceof Platform)) continue;
      Platform p = (Platform) o;
      float top = p.pos.y + p.size.y;
      boolean over = x0 < p.pos.x + p.size.x && x1 > p.pos.x
                  && z0 < p.pos.z + p.size.z && z1 > p.pos.z;
      if (over && top <= y + 0.01 && (Float.isNaN(best) || top > best)) best = top;
    }
    return best;
  }

  // Drawn in world space (inside applyCamera). The depth buffer handles occlusion,
  // so there is no draw ordering. The shadow goes last because it is translucent.
  void display(Player player) {
    noStroke();
    for (GameObject o : objects) o.display();
    player.display();
    player.displayShadow();
  }
}

PVector readVec(JSONArray a) {
  return new PVector(a.getFloat(0), a.getFloat(1), a.getFloat(2));
}
