import java.util.PriorityQueue;

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

  void display(float t, Player player) {
    noStroke();
    ArrayList<GameObject> toDraw = new ArrayList<GameObject>(objects);
    toDraw.add(player);
    for (GameObject o : depthSort(toDraw)) o.display(t);
  }
}

// Overlap allowed when deciding draw order, so objects that touch (or are a hair
// inside each other from float error) still get a clear order.
final float SORT_EPS = 0.1;

// true if a must be drawn before b (a is fully behind b on some axis)
boolean behind(GameObject a, GameObject b) {
  PVector aMin = a.minB(), aMax = a.maxB();
  PVector bMin = b.minB(), bMax = b.maxB();
  return aMin.x >= bMax.x - SORT_EPS     // a is on the +x side (camera sees -x)
      || aMax.z <= bMin.z + SORT_EPS     // a is on the -z side (camera sees +z)
      || aMax.y <= bMin.y + SORT_EPS;    // a is below b (camera sees +y)
}

// Orders objects far to near (Kahn's algorithm). When the depth rule leaves
// several objects free, the farthest by depthKey goes first. Cycles (from
// overlapping objects) are broken by forcing out the farthest remaining object.
ArrayList<GameObject> depthSort(ArrayList<GameObject> objs) {
  int n = objs.size();
  final float[] key = new float[n];
  int[] inDegree = new int[n];
  ArrayList<ArrayList<Integer>> after = new ArrayList<ArrayList<Integer>>();

  for (int i = 0; i < n; i++) {
    key[i] = objs.get(i).depthKey();
    after.add(new ArrayList<Integer>());
  }
  for (int i = 0; i < n; i++) {
    for (int j = 0; j < n; j++) {
      if (i != j && behind(objs.get(i), objs.get(j))) {
        after.get(i).add(j);  // i is drawn before j
        inDegree[j]++;
      }
    }
  }

  PriorityQueue<Integer> ready = new PriorityQueue<Integer>((a, b) -> Float.compare(key[a], key[b]));
  for (int i = 0; i < n; i++) {
    if (inDegree[i] == 0) ready.add(i);
  }

  boolean[] done = new boolean[n];
  ArrayList<GameObject> out = new ArrayList<GameObject>();
  while (out.size() < n) {
    if (ready.isEmpty()) {
      // cycle: release the farthest object not yet drawn
      int pick = -1;
      for (int i = 0; i < n; i++) {
        if (!done[i] && inDegree[i] > 0 && (pick < 0 || key[i] < key[pick])) pick = i;
      }
      inDegree[pick] = 0;
      ready.add(pick);
    }
    int i = ready.poll();
    done[i] = true;
    out.add(objs.get(i));
    for (int j : after.get(i)) {
      if (--inDegree[j] == 0) ready.add(j);
    }
  }
  return out;
}

PVector readVec(JSONArray a) {
  return new PVector(a.getFloat(0), a.getFloat(1), a.getFloat(2));
}
