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

  boolean collides(PVector center, float r, boolean is3D) {
    for (GameObject o : objects) {
      if (o.collides(center, r, is3D)) return true;
    }
    return false;
  }

  // Height of the highest box top directly under (x, z) at or below y, or NaN if none
  float groundBelow(float x, float y, float z) {
    float best = Float.NaN;
    for (GameObject o : objects) {
      if (!(o instanceof Platform)) continue;
      Platform p = (Platform) o;
      float top = p.pos.y + p.size.y;
      boolean over = x >= p.pos.x && x <= p.pos.x + p.size.x
                  && z >= p.pos.z && z <= p.pos.z + p.size.z;
      if (over && top <= y + 0.01 && (Float.isNaN(best) || top > best)) best = top;
    }
    return best;
  }

  void display(float t, Player player, float dt) {
    ArrayList<Cell> order = grid.drawOrder();
    int slot = playerSlot(order, t, player);

    PVector p = worldToScreen(player.pos.x, player.pos.y + player.radius, player.pos.z, t);
    float r = player.radius * screenScale(t);
    float k = 1 - exp(-dt * COVER_FADE_SPEED);
    float coveredAlpha = lerp(255, COVER_ALPHA, t);  // only fade in iso, blending with the view

    // Update every cell's fade before drawing any, so cells drawn earlier already
    // know which neighbours are see-through this frame
    for (int i = 0; i < order.size(); i++) {
      Cell c = order.get(i);
      // only cells drawn after the player can cover it
      float target = i >= slot && coversPlayer(c, p, r, t) ? coveredAlpha : 255;
      float alpha = fade.getOrDefault(c, 255f);
      alpha += (target - alpha) * k;
      if (alpha > 254.5) fade.remove(c);  // fully opaque cells are not stored
      else fade.put(c, alpha);
    }

    for (int i = 0; i < order.size(); i++) {
      if (i == slot) player.display(t);
      Cell c = order.get(i);
      grid.drawCell(c, t, fade.getOrDefault(c, 255f), false);
    }
    if (slot == order.size()) player.display(t);
  }

  // true if any visible face of a block overlaps the player's circle on screen.
  // The circle is approximated by its centre and 8 points just inside its edge.
  boolean coversPlayer(Cell c, PVector p, float r, float t) {
    if (c.type == BLOCK_DOT) return false;
    PVector s = grid.screenCenter(c, t);
    if (abs(s.x - p.x) > cellReach(t) + r || abs(s.y - p.y) > cellReach(t) + r) return false;

    for (int f = 0; f < 3; f++) {
      if (!grid.faceVisible(c, f)) continue;
      PVector[] q = grid.faceCorners(c.x, c.y, c.z, f, t);
      if (inQuad(p.x, p.y, q)) return true;
      for (int i = 0; i < 8; i++) {
        float a = TWO_PI * i / 8;
        if (inQuad(p.x + cos(a) * r * 0.85, p.y + sin(a) * r * 0.85, q)) return true;
      }
    }
    return false;
  }

  // Cells are already in exact painter's order, so the player only needs to be slotted
  // in among the cells it overlaps on screen. Each candidate slot is scored by how many
  // of those cells would end up on the wrong side of the player; the best one wins
  // (later slots win ties, so the player stays on top when it is ambiguous).
  int playerSlot(ArrayList<Cell> order, float t, Player player) {
    PVector p = worldToScreen(player.pos.x, player.pos.y + player.radius, player.pos.z, t);
    float reach = cellReach(t) + player.radius * screenScale(t) + 1;
    PVector pMin = player.minB(), pMax = player.maxB();

    ArrayList<Integer> idx = new ArrayList<Integer>();
    ArrayList<Boolean> before = new ArrayList<Boolean>();  // cell must be drawn before the player
    ArrayList<Boolean> after = new ArrayList<Boolean>();   // cell must be drawn after the player
    for (int i = 0; i < order.size(); i++) {
      Cell c = order.get(i);
      PVector s = grid.screenCenter(c, t);
      if (abs(s.x - p.x) > reach || abs(s.y - p.y) > reach) continue;

      PVector cMin = c.minB(), cMax = c.maxB();
      boolean cellBehind = behind(cMin, cMax, pMin, pMax);
      boolean playerBehind = behind(pMin, pMax, cMin, cMax);
      if (cellBehind == playerBehind) continue;  // no clear answer, does not constrain
      idx.add(i);
      before.add(cellBehind);
      after.add(playerBehind);
    }
    if (idx.isEmpty()) return order.size();

    int bestSlot = order.size();
    int bestCost = Integer.MAX_VALUE;
    // candidate slots: just before each constraining cell, or at the very end
    for (int k = idx.size(); k >= 0; k--) {
      int slot = k < idx.size() ? idx.get(k) : order.size();
      int cost = 0;
      for (int j = 0; j < idx.size(); j++) {
        boolean drawnFirst = idx.get(j) < slot;
        if (drawnFirst && after.get(j)) cost++;
        if (!drawnFirst && before.get(j)) cost++;
      }
      if (cost < bestCost) {
        bestCost = cost;
        bestSlot = slot;
      }
    }
    return bestSlot;
  }
}

// Blocks in front of the player fade to this alpha in iso view (255 = opaque)
final float COVER_ALPHA = 90;
final float COVER_FADE_SPEED = 12;  // higher = fades faster

// Overlap allowed when deciding draw order. The player's collision sphere is
// slightly smaller than its drawn size, so it can rest a little inside a surface.
// Must stay well below the thinnest object (0.5) or it would create false orderings.
final float SORT_EPS = 0.1;

// true if box a must be drawn before box b (a is fully behind b on some axis)
boolean behind(PVector aMin, PVector aMax, PVector bMin, PVector bMax) {
  return aMin.x >= bMax.x - SORT_EPS     // a is on the +x side (camera sees -x)
      || aMax.z <= bMin.z + SORT_EPS     // a is on the -z side (camera sees +z)
      || aMax.y <= bMin.y + SORT_EPS;    // a is below b (camera sees +y)
}

PVector readVec(JSONArray a) {
  return new PVector(a.getFloat(0), a.getFloat(1), a.getFloat(2));
}
