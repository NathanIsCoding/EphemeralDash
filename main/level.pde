class Level {
  int sizeX, sizeY, sizeZ;
  int originX, originZ;
  int[][][] cells;      // 0 = empty, 1 = cube, 2 = plane tile
  boolean[][] flat;     // 2D-mode collision: any solid at (x, y), any z
  PVector spawn = new PVector();

  Level(String file) {
    load(file);
    buildFlat();
  }

  void load(String file) {
    String[] lines = loadStrings(file);
    int y = 0, z = 0;
    for (String raw : lines) {
      String line = raw.trim();
      if (line.length() == 0 || line.startsWith("//")) continue;
      String[] p = splitTokens(line);
      if (p[0].equals("size")) {
        sizeX = int(p[1]); sizeY = int(p[2]); sizeZ = int(p[3]);
        originX = -sizeX / 2;
        originZ = -sizeZ / 2;
        cells = new int[sizeX][sizeY][sizeZ];
      } else if (p[0].equals("spawn")) {
        spawn.set(float(p[1]), float(p[2]), float(p[3]));
      } else if (p[0].equals("layer")) {
        y = int(p[1]);
        z = 0;
      } else {
        if (z < sizeZ) {
          for (int x = 0; x < min(sizeX, line.length()); x++) {
            char c = line.charAt(x);
            cells[x][y][z] = (c == '#') ? 1 : (c == '=') ? 2 : 0;
          }
        }
        z++;
      }
    }
  }

  void buildFlat() {
    flat = new boolean[sizeX][sizeY];
    for (int x = 0; x < sizeX; x++)
      for (int y = 0; y < sizeY; y++)
        for (int z = 0; z < sizeZ; z++)
          if (cells[x][y][z] != 0) flat[x][y] = true;
  }

  // r = half-size of the player's box, in world units
  boolean collides(float x, float y, float z, float r, boolean is3D) {
    int x0 = floor(x - r - originX), x1 = floor(x + r - originX);
    int y0 = floor(y - r), y1 = floor(y + r);
    int z0 = floor(z - r - originZ), z1 = floor(z + r - originZ);

    for (int ix = x0; ix <= x1; ix++) {
      for (int iy = y0; iy <= y1; iy++) {
        if (ix < 0 || ix >= sizeX || iy < 0 || iy >= sizeY) continue;
        if (!is3D) {
          if (flat[ix][iy]) return true;
        } else {
          for (int iz = z0; iz <= z1; iz++) {
            if (iz < 0 || iz >= sizeZ) continue;
            if (cells[ix][iy][iz] != 0) return true;
          }
        }
      }
    }
    return false;
  }

  // Back to front in iso: ascending x + z, then ascending y
  void display(float t) {
    for (int s = 0; s <= sizeX + sizeZ - 2; s++) {
      for (int ix = 0; ix < sizeX; ix++) {
        int iz = s - ix;
        if (iz < 0 || iz >= sizeZ) continue;
        for (int iy = 0; iy < sizeY; iy++) {
          int type = cells[ix][iy][iz];
          if (type == 1) drawCube(originX + ix, iy, originZ + iz, t);
          else if (type == 2) drawPlane(originX + ix, iy, originZ + iz, t);
        }
      }
    }
  }

  void drawCube(float x, float y, float z, float t) {
    stroke(255, 120);
    strokeWeight(1);
    fill(80, 150, 255);   // top
    face(t, x, y+1, z,   x+1, y+1, z,   x+1, y+1, z+1,   x, y+1, z+1);
    fill(50, 100, 200);   // +x side
    face(t, x+1, y, z,   x+1, y, z+1,   x+1, y+1, z+1,   x+1, y+1, z);
    fill(30, 70, 150);    // +z side (the front face in side view)
    face(t, x, y, z+1,   x+1, y, z+1,   x+1, y+1, z+1,   x, y+1, z+1);
  }

  // Flat tile: only the top face, so it collapses to a line in side view
  void drawPlane(float x, float y, float z, float t) {
    stroke(255);
    strokeWeight(2);
    if (((int)(x + z)) % 2 == 0) fill(80, 150, 255);
    else fill(60, 120, 220);
    face(t, x, y+1, z,   x+1, y+1, z,   x+1, y+1, z+1,   x, y+1, z+1);
  }

  void face(float t, float x1, float y1, float z1, float x2, float y2, float z2, float x3, float y3, float z3, float x4, float y4, float z4) {
    PVector a = worldToScreen(x1, y1, z1, t);
    PVector b = worldToScreen(x2, y2, z2, t);
    PVector c = worldToScreen(x3, y3, z3, t);
    PVector d = worldToScreen(x4, y4, z4, t);
    quad(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y);
  }
}