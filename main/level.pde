class Level {
  String name;
  PVector spawn, goal;
  ArrayList<GameObject> objects = new ArrayList<GameObject>(); // static world objects, used for collision
  CellGrid grid = new CellGrid();  // the same world split into unit cells, used for drawing
  HashMap<Cell, Float> fade = new HashMap<Cell, Float>();  // current alpha of cells that are not fully opaque

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

    grid.addBoxes(ps, BLOCK_PLATFORM);
    grid.addBoxes(cs, BLOCK_CUBE);
    grid.addDots(ds);
    grid.seeThrough = fade.keySet();  // live view: every faded cell counts as see-through
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

  // Drawn in world space (inside applyCamera). The depth buffer handles occlusion.
  // Blocks are drawn per grid cell so the ones between the camera and the player
  // can fade out individually. Translucent things go last: the shadow, then the
  // faded cells far to near. dt is 0 while paused, which freezes the fading.
  void display(Player player, float dt) {
    float t = player.shiftT;
    ArrayList<Cell> order = grid.drawOrder();
    float k = 1 - exp(-dt * COVER_FADE_SPEED);
    float coveredAlpha = lerp(255, COVER_ALPHA, t);  // only fade in iso, blending with the view
    PVector[] rays = coverRays(player, t);
    PVector eye = towardCamera(t);

    // Update every cell's fade before drawing any, so cellFaces already knows
    // which neighbours are see-through this frame
    for (Cell c : order) {
      if (c.type == BLOCK_DOT) continue;
      float target = coversPlayer(c, rays, eye) ? coveredAlpha : 255;
      float alpha = fade.getOrDefault(c, 255f);
      alpha += (target - alpha) * k;
      if (alpha > 254.5) fade.remove(c);  // fully opaque cells are not stored
      else fade.put(c, alpha);
    }

    noLights();  // flat colors per face
    noStroke();
    beginShape(QUADS);
    for (Cell c : order) {
      if (c.type != BLOCK_DOT && !fade.containsKey(c)) grid.cellFaces(c, 255, eye);
    }
    endShape();

    for (GameObject o : objects) {
      if (!(o instanceof Platform)) o.display();  // dots; boxes are drawn as cells above
    }
    player.display();
    player.displayShadow();

    // Faded cells do not write depth, so they never hide each other or the player
    noLights();
    noStroke();
    hint(DISABLE_DEPTH_MASK);
    beginShape(QUADS);
    for (Cell c : order) {
      Float alpha = fade.get(c);
      if (alpha != null) grid.cellFaces(c, alpha, eye);
    }
    endShape();
    hint(ENABLE_DEPTH_MASK);
  }

  // Ray starts for the cover test: the player's centre and 8 points just inside the
  // edge of its ball as seen from the camera
  PVector[] coverRays(Player player, float t) {
    PVector eye = towardCamera(t);
    PVector u = eye.cross(new PVector(0, 1, 0)).normalize();  // screen horizontal
    PVector v = u.cross(eye).normalize();                     // screen vertical
    PVector c = player.center();
    float r = player.half * 0.85;

    PVector[] out = new PVector[9];
    out[0] = c;
    for (int i = 0; i < 8; i++) {
      float a = TWO_PI * i / 8;
      out[i + 1] = PVector.add(c, PVector.add(PVector.mult(u, cos(a) * r), PVector.mult(v, sin(a) * r)));
    }
    return out;
  }

  // true if a block sits between any of the rays' starts and the camera
  boolean coversPlayer(Cell c, PVector[] rays, PVector eye) {
    PVector mn = c.minB(), mx = c.maxB();
    for (PVector o : rays) {
      if (rayHitsBox(o, eye, mn, mx)) return true;
    }
    return false;
  }
}

// Blocks in front of the player fade to this alpha in iso view (255 = opaque)
final float COVER_ALPHA = 90;
final float COVER_FADE_SPEED = 12;  // higher = fades faster

// Does the ray o + s * d (s >= 0) pass through the box [mn, mx]?
boolean rayHitsBox(PVector o, PVector d, PVector mn, PVector mx) {
  return rayEntry(o, d, mn, mx) >= 0;
}

// Slab test: the s at which the ray o + s * d (s >= 0) enters the box [mn, mx]
// (0 if it starts inside), or -1 if it misses
float rayEntry(PVector o, PVector d, PVector mn, PVector mx) {
  float near = 0, far = Float.MAX_VALUE;
  for (int a = 0; a < 3; a++) {
    float oa = getAxis(o, a), da = getAxis(d, a);
    float lo = getAxis(mn, a), hi = getAxis(mx, a);
    if (abs(da) < 1e-6) {
      if (oa < lo || oa > hi) return -1;  // parallel to this slab and outside it
      continue;
    }
    float s1 = (lo - oa) / da, s2 = (hi - oa) / da;
    near = max(near, min(s1, s2));
    far = min(far, max(s1, s2));
    if (near > far) return -1;
  }
  return near;
}

PVector readVec(JSONArray a) {
  return new PVector(a.getFloat(0), a.getFloat(1), a.getFloat(2));
}
