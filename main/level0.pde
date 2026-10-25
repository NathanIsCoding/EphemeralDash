class Level0 {
  int sizeX = 12;
  int sizeZ = 12;
  int originX = -6;  // centers the plane on the world origin
  int originZ = -6;

  void display(float t) {
    stroke(255, 120);
    strokeWeight(1);

    for (int ix = 0; ix < sizeX; ix++) {
      for (int iz = 0; iz < sizeZ; iz++) {
        float x = originX + ix;
        float z = originZ + iz;

        PVector a = worldToScreen(x,     0, z,     t);
        PVector b = worldToScreen(x + 1, 0, z,     t);
        PVector c = worldToScreen(x + 1, 0, z + 1, t);
        PVector d = worldToScreen(x,     0, z + 1, t);

        if ((ix + iz) % 2 == 0) fill(60, 120, 220);
        else fill(40, 90, 180);

        quad(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y);
      }
    }
  }
}