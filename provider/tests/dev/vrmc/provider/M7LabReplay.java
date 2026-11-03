package dev.vrmc.provider;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.List;
import java.util.Locale;

/**
 * Replays Gesture Lab recordings through the real {@link VisionM7Gesture} state machine and emits
 * every action event, so threshold/classifier changes can be scored against labelled operator data
 * before device testing.
 *
 * <p>Data path: raw JSONL (gitignored) is converted once by scripts/m7_lab_fixture.py into a
 * compact binary fixture (also gitignored); this harness reads only the fixture. That keeps replay
 * fast (~10 k frames in well under a second) and makes the evaluation reproducible on any machine
 * that has the recordings.
 *
 * <p>This is a host analysis tool, not device evidence: recorded frames are ~18 Hz while the game
 * runs at ~60-90 Hz, so absolute velocities are smoothed and must not be used to justify device
 * behaviour. The gate is "does the state machine see the labelled gestures, and does it stay quiet
 * on IDLE", with margins recorded in docs/mvp/M7_ENGINE.md.
 *
 * <p>Usage (from repo root):
 * <pre>
 *   java -cp ... dev.vrmc.provider.M7LabReplay [--fixtures DIR] [--out DIR] [--features] [--quiet]
 * </pre>
 */
public final class M7LabReplay {
    private static final int JOINTS = 27;
    private static final int FLOATS = JOINTS * 3;
    private static final int HEADER_BYTES = 16;
    private static final int RECORD_BYTES = 8 + 1 + 12 + 64 + FLOATS * 4 + FLOATS * 4;
    private static final byte[] MAGIC = {'V', 'R', 'M', 'C', 'L', 'A', 'B', 1};

    private static final String[] HELD_ACTIONS = {
        "break", "teleport", "walk", "bowDraw", "eat", "sneak", "climbGrabLeft", "climbGrabRight"
    };
    private static final String[] PULSE_ACTIONS = {
        "place", "attack", "menu", "inventory", "hotbarNext", "hotbarPrev", "bowFire", "guiClick",
        "climbJump", "jump", "leftFistTap"
    };

    private static final String FEATURE_HEADER =
        "frame,t_ms,headY,trL,trR,pinchL,pinchR,curlL,curlR,speedL,speedR,tipSpeedR,"
        + "winSpeedL,winSpeedR,winHeadVel,actions";

    private static int failures;

    public static void main(String[] args) throws Exception {
        Path fixtures = Paths.get("export/m7-lab-fixtures");
        Path out = Paths.get("export/m7-replay");
        boolean features = false;
        boolean quiet = false;
        String contextMode = "auto";
        String debugId = null;
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--fixtures" -> fixtures = Paths.get(args[++i]);
                case "--out" -> out = Paths.get(args[++i]);
                case "--features" -> features = true;
                case "--quiet" -> quiet = true;
                case "--context" -> contextMode = args[++i];
                case "--debug" -> debugId = args[++i];
                case "--help", "-h" -> { usage(); return; }
                default -> {
                    System.err.println("[m7-replay] unknown arg: " + args[i]);
                    usage();
                    System.exit(2);
                }
            }
        }
        if (!Files.isDirectory(fixtures)) {
            System.err.println("[m7-replay] missing fixture dir: " + fixtures
                + " (run scripts/m7_lab_fixture.py first)");
            System.exit(2);
        }
        Files.createDirectories(out);
        List<Path> bins;
        try (var stream = Files.list(fixtures)) {
            bins = stream.filter(p -> p.getFileName().toString().endsWith(".bin"))
                .sorted()
                .toList();
        }
        if (bins.isEmpty()) {
            System.err.println("[m7-replay] no .bin fixtures in " + fixtures);
            System.exit(2);
        }
        Path eventsPath = out.resolve("events.jsonl");
        Path summaryPath = out.resolve("summary.txt");
        StringBuilder summary = new StringBuilder(4096);
        summary.append("M7 lab replay summary\n");
        summary.append("fixtures=").append(fixtures.toAbsolutePath()).append('\n');
        summary.append(String.format(Locale.ROOT, "%-58s %6s %8s  %s%n", "dataset", "frames", "dur_s", "action activity"));
        try (BufferedWriter events = Files.newBufferedWriter(eventsPath, StandardCharsets.UTF_8)) {
            for (Path bin : bins) {
                String id = bin.getFileName().toString();
                id = id.substring(0, id.length() - ".bin".length());
                String label = datasetLabel(id);
                ReplayResult r = replay(id, label, bin, events, features ? out : null, contextMode,
                    debugId);
                summary.append(String.format(Locale.ROOT, "%-58s %6d %8.2f  %s%n",
                    id, r.frames, r.durationS, r.activity));
                if (!quiet) {
                    System.out.printf(Locale.ROOT, "[m7-replay] %-58s frames=%d dur=%.2fs %s%n",
                        id, r.frames, r.durationS, r.detail);
                }
            }
        }
        summary.append("\nLegend: pulse=rising edges, held=state runs (count/active-frames).\n");
        Files.writeString(summaryPath, summary.toString(), StandardCharsets.UTF_8);
        System.out.println("[m7-replay] events -> " + eventsPath.toAbsolutePath());
        System.out.println("[m7-replay] summary -> " + summaryPath.toAbsolutePath());
        if (failures != 0) {
            System.out.println("[m7-replay] FAIL, datasets=" + failures + " failed");
            System.exit(1);
        }
        System.out.println("[m7-replay] DONE");
    }

    private static void usage() {
        System.out.println("usage: M7LabReplay [--fixtures DIR] [--out DIR] [--features] [--quiet]");
    }

    /** Game context implied by the recording's labelled scenario (the lab has no items held). */
    static int labelContext(String label) {
        if ("BOW_BOTH_FISTS".equals(label)) return VisionM7Gesture.CTX_BOW_HELD;
        if ("EAT_RIGHT_HAND_HEAD".equals(label)) return VisionM7Gesture.CTX_EDIBLE_HELD;
        if ("CLIMB_ALTERNATE".equals(label)) return VisionM7Gesture.CTX_CLIMBABLE;
        return 0;
    }

    /** gesturelab-<LABEL>-<YYYYMMDD>-<HHMMSS> -> LABEL (IDLE stays IDLE). */
    static String datasetLabel(String id) {
        String s = id.startsWith("gesturelab-") ? id.substring("gesturelab-".length()) : id;
        int cut = s.lastIndexOf('-');
        if (cut > 0) {
            String tail = s.substring(cut + 1);
            if (tail.length() == 6 && tail.chars().allMatch(Character::isDigit)) {
                s = s.substring(0, cut);
                cut = s.lastIndexOf('-');
                if (cut > 0) {
                    String date = s.substring(cut + 1);
                    if (date.length() == 8 && date.chars().allMatch(Character::isDigit)) {
                        s = s.substring(0, cut);
                    }
                }
            }
        }
        return s;
    }

    private static final class ReplayResult {
        int frames;
        double durationS;
        String activity = "";
        String detail = "";
    }

    private static ReplayResult replay(String id, String label, Path bin, BufferedWriter events,
                                       Path featureDir, String contextMode, String debugId)
        throws IOException {
        ByteBuffer buf;
        try (FileChannel ch = FileChannel.open(bin, StandardOpenOption.READ)) {
            if (ch.size() < HEADER_BYTES) {
                throw new IOException("short fixture: " + bin);
            }
            buf = ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size()).order(ByteOrder.LITTLE_ENDIAN);
        }
        for (int i = 0; i < MAGIC.length; i++) {
            if (buf.get(HEADER_BYTES - 16 + i) != MAGIC[i]) {
                throw new IOException("bad fixture magic: " + bin);
            }
        }
        int version = buf.getInt(8);
        if (version != 1) {
            throw new IOException("unsupported fixture version " + version + ": " + bin);
        }
        int frameCount = buf.getInt(12);
        long expected = HEADER_BYTES + (long) frameCount * RECORD_BYTES;
        if (buf.capacity() < expected) {
            throw new IOException("truncated fixture " + bin + " (" + buf.capacity() + " < " + expected + ")");
        }

        boolean contextGating = !"off".equalsIgnoreCase(contextMode);
        VisionM7Gesture gesture = new VisionM7Gesture(
            VisionM7Gesture.PINCH_ON, VisionM7Gesture.PINCH_OFF,
            VisionM7Gesture.FIST_ON, VisionM7Gesture.FIST_OFF, contextGating);
        int labelContext = labelContext(label);
        if ("none".equalsIgnoreCase(contextMode)) {
            labelContext = 0;
        }
        float[] jointsL = new float[FLOATS];
        float[] jointsR = new float[FLOATS];
        float[] prevPosL = new float[3];
        float[] prevPosR = new float[3];
        float[] prevTipR = new float[3];
        float[] prevHead = new float[3];
        boolean havePrev = false;
        double t0 = 0.0;
        double prevT = 0.0;
        double lastHeadX = 0.0, lastHeadY = 1.5, lastHeadZ = 0.0;

        boolean[] prevAction = new boolean[HELD_ACTIONS.length + PULSE_ACTIONS.length];
        long[] runStartNs = new long[HELD_ACTIONS.length];
        long[] runStartFrame = new long[HELD_ACTIONS.length];
        // Counts for the one-line activity string.
        int[] heldRuns = new int[HELD_ACTIONS.length];
        int[] heldFrames = new int[HELD_ACTIONS.length];
        int[] pulses = new int[PULSE_ACTIONS.length];
        long[] pulseFirstNs = new long[PULSE_ACTIONS.length];
        long[] pulseLastNs = new long[PULSE_ACTIONS.length];
        boolean[] pulseOnce = new boolean[PULSE_ACTIONS.length];
        long[] lastRunStartNs = new long[HELD_ACTIONS.length];
        long[] lastRunEndNs = new long[HELD_ACTIONS.length];

        long firstNs = 0L;
        long lastNs = 0L;
        BufferedWriter feat = null;
        if (featureDir != null) {
            Path fp = featureDir.resolve("features-" + id + ".csv");
            feat = Files.newBufferedWriter(fp, StandardCharsets.UTF_8);
            feat.write(FEATURE_HEADER);
            feat.newLine();
        }
        try {
            int offset = HEADER_BYTES;
            for (int frame = 0; frame < frameCount; frame++) {
                double t = buf.getDouble(offset);
                int flags = buf.get(offset + 8) & 0xFF;
                float hx = buf.getFloat(offset + 9);
                float hy = buf.getFloat(offset + 13);
                float hz = buf.getFloat(offset + 17);
                offset += 21;
                float[] headM = new float[16];
                for (int i = 0; i < 16; i++) {
                    headM[i] = buf.getFloat(offset + i * 4);
                }
                offset += 64;
                for (int i = 0; i < FLOATS; i++) {
                    jointsL[i] = buf.getFloat(offset + i * 4);
                }
                offset += FLOATS * 4;
                for (int i = 0; i < FLOATS; i++) {
                    jointsR[i] = buf.getFloat(offset + i * 4);
                }
                offset += FLOATS * 4;

                boolean headTracked = (flags & 1) != 0;
                boolean trL = (flags & 2) != 0;
                boolean trR = (flags & 4) != 0;
                if (frame == 0) {
                    t0 = t;
                }
                if (!headTracked) {
                    hx = (float) lastHeadX;
                    hy = (float) lastHeadY;
                    hz = (float) lastHeadZ;
                } else {
                    lastHeadX = hx;
                    lastHeadY = hy;
                    lastHeadZ = hz;
                }
                double rel = t - t0;
                long nowNs = (long) Math.round(t * 1.0e9);
                if (frame == 0) {
                    firstNs = nowNs;
                }
                lastNs = nowNs;
                float pinchL = trL ? distF(jointsL, 4, 9) : Float.NaN;
                float pinchR = trR ? distF(jointsR, 4, 9) : Float.NaN;

                float hrX = 1.0F, hrY = 0.0F, hrZ = 0.0F;
                float hfX = 0.0F, hfY = 0.0F, hfZ = -1.0F;
                float m0 = headM[0], m1 = headM[1], m2 = headM[2];
                float m8 = headM[8], m9 = headM[9], m10 = headM[10];
                float rn = (float) Math.sqrt(m0 * m0 + m1 * m1 + m2 * m2);
                float bn = (float) Math.sqrt(m8 * m8 + m9 * m9 + m10 * m10);
                if (rn > 1.0e-4F && bn > 1.0e-4F) {
                    hrX = m0 / rn; hrY = m1 / rn; hrZ = m2 / rn;
                    hfX = -m8 / bn; hfY = -m9 / bn; hfZ = -m10 / bn;
                }
                gesture.update(trL, jointsL, trR, jointsR, pinchL, pinchR, hx, hy, hz,
                    hrX, hrY, hrZ, hfX, hfY, hfZ, nowNs, labelContext);

                // 100 ms windowed displacement velocities (analysis cross-check only).
                double dtWin = Math.max(1.0e-3, rel - prevT);
                float winSpeedL = 0f, winSpeedR = 0f, winHeadVel = 0f;
                if (havePrev && offsetsFinite(jointsL, 0, trL) && offsetsFinite(prevPosL, 0, true)) {
                    winSpeedL = dist3(jointsL, 0, prevPosL) / (float) dtWin;
                }
                if (havePrev && offsetsFinite(jointsR, 0, trR) && offsetsFinite(prevPosR, 0, true)) {
                    winSpeedR = dist3(jointsR, 0, prevPosR) / (float) dtWin;
                }
                if (havePrev) {
                    winHeadVel = (float) ((hy - prevHead[1]) / dtWin);
                }

                boolean[] curHeld = new boolean[HELD_ACTIONS.length];
                curHeld[0] = gesture.breakHeld();
                curHeld[1] = gesture.teleportHeld();
                curHeld[2] = gesture.walkActive();
                curHeld[3] = gesture.bowDraw();
                curHeld[4] = gesture.eat();
                curHeld[5] = gesture.sneak();
                curHeld[6] = gesture.climbGrabLeft();
                curHeld[7] = gesture.climbGrabRight();
                boolean[] curPulse = new boolean[PULSE_ACTIONS.length];
                curPulse[0] = gesture.place();
                curPulse[1] = gesture.attack();
                curPulse[2] = gesture.menu();
                curPulse[3] = gesture.inventory();
                curPulse[4] = gesture.hotbarNext();
                curPulse[5] = gesture.hotbarPrev();
                curPulse[6] = gesture.bowFire();
                curPulse[7] = gesture.guiClick();
                curPulse[8] = gesture.climbJump();
                curPulse[9] = gesture.jump();
                curPulse[10] = gesture.leftFistTap();

                int actionMask = 0;
                for (int i = 0; i < curHeld.length; i++) {
                    if (curHeld[i]) {
                        heldFrames[i]++;
                        actionMask |= 1 << i;
                        if (!prevAction[i]) {
                            runStartNs[i] = nowNs;
                            runStartFrame[i] = frame;
                            heldRuns[i]++;
                            lastRunStartNs[i] = nowNs;
                        }
                    } else if (prevAction[i]) {
                        lastRunEndNs[i] = nowNs;
                        double startRel = (runStartNs[i] - firstNs) * 1.0e-9;
                        double durMs = (nowNs - runStartNs[i]) * 1.0e-6;
                        events.write(String.format(Locale.ROOT,
                            "{\"dataset\":\"%s\",\"label\":\"%s\",\"action\":\"%s\","
                            + "\"kind\":\"held\",\"t_ms\":%.1f,\"dur_ms\":%.1f,\"start_frame\":%d}\n",
                            id, label, HELD_ACTIONS[i], startRel * 1000.0, durMs, runStartFrame[i]));
                    }
                }
                for (int i = 0; i < curPulse.length; i++) {
                    int bit = HELD_ACTIONS.length + i;
                    if (curPulse[i]) {
                        actionMask |= 1 << bit;
                        if (!prevAction[bit]) {
                            pulses[i]++;
                            pulseOnce[i] = true;
                            long base = firstNs;
                            events.write(String.format(Locale.ROOT,
                                "{\"dataset\":\"%s\",\"label\":\"%s\",\"action\":\"%s\","
                                + "\"kind\":\"pulse\",\"t_ms\":%.1f,\"frame\":%d}\n",
                                id, label, PULSE_ACTIONS[i], (nowNs - base) * 1.0e-6, frame));
                        }
                    }
                    prevAction[bit] = curPulse[i];
                }
                for (int i = 0; i < curHeld.length; i++) {
                    prevAction[i] = curHeld[i];
                }

                if (debugId != null && debugId.equals(id) && frame % 9 == 0) {
                    float fwdL = (jointsL[0] - hx) * hfX + (jointsL[1] - hy) * hfY + (jointsL[2] - hz) * hfZ;
                    float fwdR = (jointsR[0] - hx) * hfX + (jointsR[1] - hy) * hfY + (jointsR[2] - hz) * hfZ;
                    System.out.printf(java.util.Locale.ROOT,
                        "DBG f=%d t=%.2f tr=%b/%b fwd=%.3f/%.3f diff=%.3f walk=%b bow=%b | %s%n",
                        frame, rel, trL, trR, fwdL, fwdR, fwdL - fwdR,
                        gesture.walkActive(), gesture.bowDraw(), gesture.debugState());
                }
                if (feat != null) {
                    float curlL = trL ? curl(jointsL) : Float.NaN;
                    float curlR = trR ? curl(jointsR) : Float.NaN;
                    float speedL = 0f, speedR = 0f, tipSpeedR = 0f;
                    if (havePrev && trL) {
                        speedL = dist3(jointsL, 0, prevPosL) / (float) dtWin;
                    }
                    if (havePrev && trR) {
                        speedR = dist3(jointsR, 0, prevPosR) / (float) dtWin;
                        tipSpeedR = dist3(jointsR, 9, prevTipR) / (float) dtWin;
                    }
                    feat.write(String.format(Locale.ROOT,
                        "%d,%.1f,%.4f,%d,%d,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d",
                        frame, rel * 1000.0, hy, trL ? 1 : 0, trR ? 1 : 0,
                        finite(pinchL), finite(pinchR), finite(curlL), finite(curlR),
                        speedL, speedR, tipSpeedR, winSpeedL, winSpeedR, winHeadVel, actionMask));
                    feat.newLine();
                }

                savePos(jointsL, trL, prevPosL);
                savePos(jointsR, trR, prevPosR);
                if (trR) {
                    copyPos(jointsR, 9, prevTipR);
                }
                prevHead[0] = (float) lastHeadX;
                prevHead[1] = hy;
                prevHead[2] = (float) lastHeadZ;
                prevT = rel;
                havePrev = true;
            }
            // Flush any held action still active at end of recording.
            long nowNs = lastNs;
            for (int i = 0; i < prevAction.length && i < HELD_ACTIONS.length; i++) {
                if (prevAction[i] && runStartNs[i] != 0L) {
                    double startRel = (runStartNs[i] - firstNs) * 1.0e-9;
                    double durMs = (nowNs - runStartNs[i]) * 1.0e-6;
                    events.write(String.format(Locale.ROOT,
                        "{\"dataset\":\"%s\",\"label\":\"%s\",\"action\":\"%s\","
                        + "\"kind\":\"held\",\"t_ms\":%.1f,\"dur_ms\":%.1f,\"start_frame\":%d}\n",
                        id, label, HELD_ACTIONS[i], startRel * 1000.0, durMs, runStartFrame[i]));
                }
            }
        } finally {
            if (feat != null) {
                feat.close();
            }
        }
        ReplayResult r = new ReplayResult();
        r.frames = frameCount;
        r.durationS = (lastNs - firstNs) * 1.0e-9;
        StringBuilder a = new StringBuilder();
        for (int i = 0; i < HELD_ACTIONS.length; i++) {
            if (heldRuns[i] > 0) {
                a.append(HELD_ACTIONS[i]).append("=").append(heldRuns[i]).append('/')
                    .append(heldFrames[i]).append(' ');
            }
        }
        for (int i = 0; i < PULSE_ACTIONS.length; i++) {
            if (pulses[i] > 0) {
                a.append(PULSE_ACTIONS[i]).append('=').append(pulses[i]).append(' ');
            }
        }
        r.activity = a.toString().trim();
        r.detail = "events=" + r.activity;
        return r;
    }

    private static void copyPos(float[] joints, int index, float[] out) {
        int o = index * 3;
        out[0] = joints[o];
        out[1] = joints[o + 1];
        out[2] = joints[o + 2];
    }

    private static void savePos(float[] joints, boolean tracked, float[] out) {
        if (tracked) {
            copyPos(joints, 0, out);
        }
    }

    private static boolean offsetsFinite(float[] joints, int index, boolean tracked) {
        if (!tracked) {
            return false;
        }
        int o = index * 3;
        return Float.isFinite(joints[o]) && Float.isFinite(joints[o + 1]) && Float.isFinite(joints[o + 2]);
    }

    private static float distF(float[] joints, int a, int b) {
        int ao = a * 3, bo = b * 3;
        float dx = joints[ao] - joints[bo];
        float dy = joints[ao + 1] - joints[bo + 1];
        float dz = joints[ao + 2] - joints[bo + 2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static float dist3(float[] joints, int a, float[] pos) {
        int ao = a * 3;
        float dx = joints[ao] - pos[0];
        float dy = joints[ao + 1] - pos[1];
        float dz = joints[ao + 2] - pos[2];
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static float dist3f(float ax, float ay, float az, float bx, float by, float bz) {
        float dx = ax - bx, dy = ay - by, dz = az - bz;
        return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    /** Same curl ratio as the engine/Gesture Lab: mean(tip->knuckle / wrist->knuckle). */
    private static float curl(float[] joints) {
        int[] knuckles = {6, 11, 16, 21};
        int[] tips = {9, 14, 19, 24};
        float sum = 0.0F;
        for (int i = 0; i < 4; i++) {
            int ko = knuckles[i] * 3;
            int to = tips[i] * 3;
            float wx = joints[knuckles[i] * 3] - joints[0];
            float wy = joints[knuckles[i] * 3 + 1] - joints[1];
            float wz = joints[knuckles[i] * 3 + 2] - joints[2];
            float wrist = (float) Math.sqrt(wx * wx + wy * wy + wz * wz);
            float dx = joints[to] - joints[ko];
            float dy = joints[to + 1] - joints[ko + 1];
            float dz = joints[to + 2] - joints[ko + 2];
            float c = (float) Math.sqrt(dx * dx + dy * dy + dz * dz) / Math.max(0.02F, wrist);
            sum += Math.max(0.0F, Math.min(2.0F, c));
        }
        return sum * 0.25F;
    }

    private static double finite(float v) {
        return Float.isFinite(v) ? v : 0.0;
    }
}
