import ddf.minim.*;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

// Per-level music. A level names its track in its file ("music": "song.mp3"); tracks
// live in data/music/. Minim streams them from disk, so even long tracks load quickly.
//
// The track starts from the beginning on every attempt, pauses with the game, stops
// on death and when leaving to the menus.

final String MUSIC_DIR = "music";
final String[] MUSIC_EXTENSIONS = { ".mp3", ".wav" };

Minim minim;  // made in setup()

boolean isMusicFile(String name) {
  String n = name.toLowerCase();
  for (String ext : MUSIC_EXTENSIONS) if (n.endsWith(ext)) return true;
  return false;
}

// The track files in data/music, sorted by name
String[] musicTracks() {
  String[] files = new File(dataPath(MUSIC_DIR)).list();
  ArrayList<String> tracks = new ArrayList<String>();
  if (files != null) for (String f : files) if (isMusicFile(f)) tracks.add(f);
  java.util.Collections.sort(tracks, String.CASE_INSENSITIVE_ORDER);
  return tracks.toArray(new String[0]);
}

class Music {
  AudioPlayer player;
  String track;  // file name of the loaded track, or null
  float volume = 1;  // 0..1

  void setVolume(float v) {
    volume = v;
    applyVolume();
  }

  // Minim sets loudness as gain in decibels; 0 dB is the file as recorded.
  // 20 * log10 makes the slider feel even, and 0 is a plain mute.
  void applyVolume() {
    if (player == null) return;
    if (volume <= 0.001) {
      player.mute();
    } else {
      player.unmute();
      player.setGain(20 * log(volume) / log(10));
    }
  }

  // Plays track (a file in data/music) from the start, looping. null or a missing file means silence.
  void start(String file) {
    start(file, 0);
  }

  // The same, from `seconds` into the track (wrapping round, as the track loops)
  void start(String file, float seconds) {
    if (file == null || !new File(dataPath(MUSIC_DIR + "/" + file)).exists()) {
      stop();
      return;
    }
    if (!file.equals(track)) {
      unload();
      player = minim.loadFile(MUSIC_DIR + "/" + file);
      if (player == null) {
        println("Could not load music: " + file);
        return;
      }
      track = file;
      applyVolume();
    }
    player.rewind();
    player.loop();
    int ms = round(seconds * 1000);
    if (ms > 0 && player.length() > 0) player.cue(ms % player.length());
  }

  void pause() {
    if (player != null) player.pause();
  }

  void resume() {
    if (player != null && !player.isPlaying()) player.loop();
  }

  void stop() {
    if (player == null) return;
    player.pause();
    player.rewind();
  }

  boolean playing() {
    return player != null && player.isPlaying();
  }

  void unload() {
    if (player != null) player.close();
    player = null;
    track = null;
  }
}

// The file picker reports back on its own thread, so the choice is only stored here
// and the editor picks it up on its next update.
volatile File pickedMusicFile;

void musicFileChosen(File f) {
  if (f != null) pickedMusicFile = f;
}

// Copies a picked file into data/music and returns its name there, or null on failure.
// A different file with the same name gets a number added, so other levels' tracks
// are never replaced.
String importMusic(File src) {
  if (!isMusicFile(src.getName())) return null;
  File dir = new File(dataPath(MUSIC_DIR));
  dir.mkdirs();
  String name = src.getName();
  int dot = name.lastIndexOf('.');
  String base = name.substring(0, dot), ext = name.substring(dot);
  File dest = new File(dir, name);
  for (int n = 2; dest.exists() && dest.length() != src.length(); n++) {
    dest = new File(dir, base + " (" + n + ")" + ext);
  }
  try {
    if (!dest.getCanonicalPath().equals(src.getCanonicalPath())) {
      Files.copy(src.toPath(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING);
    }
    return dest.getName();
  } catch (IOException e) {
    println("Could not import " + src + ": " + e);
    return null;
  }
}

// Editor panel for choosing the level's track: "None", every track in data/music,
// then Import... (opens a file picker) and a preview button.
final float MP_W = 300, MP_ROW = 26, MP_PAD = 8;
final int MP_MAX_ROWS = 10;  // tracks shown at once; the wheel scrolls the rest

class MusicPanel {
  String[] tracks = new String[0];
  int scroll = 0;

  void refresh() {
    tracks = musicTracks();
    scroll = constrain(scroll, 0, max(0, tracks.length + 1 - MP_MAX_ROWS));
  }

  // list rows: 0 is "None", then one per track
  int rowCount() { return tracks.length + 1; }
  int shownRows() { return min(rowCount(), MP_MAX_ROWS); }

  float x, y;  // top-left, set by the editor before use (under the music button)
  float h() { return MP_PAD * 2 + 24 + shownRows() * MP_ROW + 8 + MP_ROW; }
  float rowY(int shown) { return y + MP_PAD + 24 + shown * MP_ROW; }
  float buttonsY() { return rowY(shownRows()) + 8; }

  boolean over(float mx, float my) {
    return mx >= x && mx < x + MP_W && my >= y && my < y + h();
  }

  // Index of the list row under the mouse (0 = None), or -1
  int rowAt(float mx, float my) {
    if (mx < x || mx >= x + MP_W) return -1;
    for (int s = 0; s < shownRows(); s++) {
      if (my >= rowY(s) && my < rowY(s) + MP_ROW) return s + scroll;
    }
    return -1;
  }

  // the two buttons along the bottom: 0 = Import..., 1 = preview
  float[] buttonRect(int i) {
    float w = (MP_W - MP_PAD * 3) / 2;
    return new float[] { x + MP_PAD + i * (w + MP_PAD), buttonsY(), w, MP_ROW };
  }

  int buttonAt(float mx, float my) {
    for (int i = 0; i < 2; i++) {
      float[] r = buttonRect(i);
      if (mx >= r[0] && mx < r[0] + r[2] && my >= r[1] && my < r[1] + r[3]) return i;
    }
    return -1;
  }

  void wheel(float count) {
    scroll = constrain(scroll + (count > 0 ? 1 : -1), 0, max(0, rowCount() - MP_MAX_ROWS));
  }

  String trackFor(int row) {
    return row == 0 ? null : tracks[row - 1];
  }

  void display(String current, boolean previewing) {
    noStroke();
    fill(0, 210);
    rect(x, y, MP_W, h(), 8);

    textAlign(LEFT, CENTER);
    textSize(14);
    fill(255);
    text("Level music", x + MP_PAD + 4, y + MP_PAD + 10);
    if (tracks.length == 0) {
      fill(150);
      textSize(12);
      textAlign(RIGHT, CENTER);
      text("no tracks yet", x + MP_W - MP_PAD - 4, y + MP_PAD + 10);
    }

    int hover = rowAt(mouseX, mouseY);
    textSize(13);
    textAlign(LEFT, CENTER);
    for (int s = 0; s < shownRows(); s++) {
      int row = s + scroll;
      String t = trackFor(row);
      boolean on = t == null ? current == null : t.equals(current);
      float ry = rowY(s);
      if (on || row == hover) {
        fill(on ? color(255, 200, 60, 60) : color(255, 25));
        rect(x + 4, ry, MP_W - 8, MP_ROW, 4);
      }
      fill(on ? color(255, 200, 60) : t == null ? color(160) : color(230));
      String label = t == null ? "None" : t;
      // keep long names inside the panel
      while (textWidth(label) > MP_W - 40 && label.length() > 4) label = label.substring(0, label.length() - 4) + "...";
      text(label, x + MP_PAD + 6, ry + MP_ROW / 2 - 1);
    }
    // scroll hints when the list is longer than the panel
    fill(150);
    textAlign(RIGHT, CENTER);
    if (scroll > 0) text("^", x + MP_W - MP_PAD - 4, rowY(0) + MP_ROW / 2);
    if (scroll + shownRows() < rowCount()) text("v", x + MP_W - MP_PAD - 4, rowY(shownRows() - 1) + MP_ROW / 2);

    int hb = buttonAt(mouseX, mouseY);
    String[] labels = { "Import...", previewing ? "Stop preview" : "Preview" };
    for (int i = 0; i < 2; i++) {
      float[] r = buttonRect(i);
      boolean disabled = i == 1 && current == null;
      fill(disabled ? color(255, 8) : i == hb ? color(255, 200, 60, 70) : color(255, 20));
      stroke(disabled ? color(255, 30) : i == hb ? color(255, 200, 60) : color(255, 70));
      strokeWeight(1);
      rect(r[0], r[1], r[2], r[3], 5);
      noStroke();
      fill(disabled ? color(110) : color(255));
      textAlign(CENTER, CENTER);
      text(labels[i], r[0] + r[2] / 2, r[1] + r[3] / 2 - 1);
    }
  }
}
